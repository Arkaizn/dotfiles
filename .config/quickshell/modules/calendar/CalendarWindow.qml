import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "CalUtil.js" as U

// Calendar app: a normal (floating) window like the settings app.
// Accounts: iCloud / any CalDAV server, .ics subscriptions (Google, Outlook,
// holidays, …) and local .ics files — see services/CalendarStore.qml and
// scripts/calendar/calsync.py.
//
// Open it with:  qs ipc call calendar toggle   (or the "Calendar" launcher entry)
// Keys: ←/→ previous/next · T today · N new event · 1-4 day/week/month/agenda
Scope {
    id: root

    // kept across shell reloads (config edits etc.): an open window comes back
    property alias open: persist.open
    property alias view: persist.view      // day | week | month | agenda
    PersistentProperties {
        id: persist
        reloadableId: "calendarWindow"
        property bool open: false
        property string view: "month"
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { if (!root.open) root.resetView(); root.open = !root.open }
        function open(): void { if (!root.open) root.resetView(); root.show() }
        function close(): void { root.open = false }
        // e.g. qs ipc call calendar setView week   ("show" clashes with `qs ipc show`)
        // e.g. qs ipc call calendar openDate 2026-10-16   (reminder notifications use it)
        function openDate(date: string): void {
            const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
            if (m) root.jumpTo = new Date(+m[1], +m[2] - 1, +m[3])
            if (root.view === "month" || root.view === "agenda") root.view = "day"
            root.show()
        }
        // new event on that day (the dashboard's right-click uses it)
        function newEvent(date: string): void {
            const d = root.parseDay(date)
            if (d) { root.pendingNew = true; root.jumpTo = d }     // flag first: the guard sees it
            if (!root.open) root.resetView()
            root.show()
        }
        // details of one event (id from CalendarStore), e.g. from the dashboard
        function showEvent(id: string): void {
            const e = CalendarStore.visibleEvents.find(x => x.id === id)
            if (e) { const d = new Date(e.start); d.setHours(0, 0, 0, 0); root.pendingEvent = id; root.jumpTo = d }
            if (!root.open) root.resetView()
            root.show()
        }
        function setView(view: string): void {
            if (["day", "week", "month", "agenda"].includes(view)) root.view = view
            root.show()
        }
    }

    readonly property string windowTitle: "Quickshell Calendar"

    // open, or bring the already open window to the front (niri focuses it,
    // switching workspace / monitor if needed)
    function show() {
        if (root.open)
            Quickshell.execDetached(["sh", "-c",
                'id=$(niri msg -j windows | jq -r --arg t "$1" \'first(.[] | select(.title == $t) | .id) // empty\'); '
                + '[ -n "$id" ] && niri msg action focus-window --id "$id"', "sh", root.windowTitle])
        root.open = true
    }


    // fresh open: the view picked in the calendar settings
    function resetView() { root.view = Settings.calendar.defaultView ?? "month" }

    // jump the open (or opening) window to a day — set by openDate()
    property var jumpTo: null
    property bool pendingNew: false        // then open the editor there
    property string pendingEvent: ""       // then show that event

    function parseDay(s) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
        return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: root.windowTitle
            implicitWidth: 1240
            implicitHeight: 800
            minimumSize: Qt.size(900, 560)
            color: "transparent"
            visible: true
            onVisibleChanged: if (!visible) root.open = false

            property date cursor: U.dayStart(new Date())

            onCursorChanged: CalendarStore.ensureRange(cursor)
            Connections {
                target: root
                // deferred, so a request that sets several of these is handled once, complete
                function onJumpToChanged() { Qt.callLater(win.takePending) }
                function onPendingNewChanged() { Qt.callLater(win.takePending) }
                function onPendingEventChanged() { Qt.callLater(win.takePending) }
            }

            function takePending() {
                // an event being written isn't thrown away for a new request
                if (eventDialog.shown && eventDialog.editing && (root.pendingNew || root.pendingEvent)) {
                    root.jumpTo = null
                    root.pendingNew = false
                    root.pendingEvent = ""
                    eventDialog.shake()
                    return
                }
                if (root.jumpTo) { cursor = root.jumpTo; root.jumpTo = null }
                if (root.pendingNew) { root.pendingNew = false; newEvent() }
                if (root.pendingEvent) {
                    const e = CalendarStore.visibleEvents.find(x => x.id === root.pendingEvent)
                    root.pendingEvent = ""
                    if (e) eventDialog.showEvent(e)
                }
            }

            Component.onCompleted: {
                Qt.callLater(takePending)       // once the dialogs exist
                CalendarStore.ensureRange(cursor)
                if (Date.now() - CalendarStore.lastSync > 60000) CalendarStore.sync()
                keys.forceActiveFocus()
            }

            // month view: scroll a month; the others: slide the new range in
            function step(dir) {
                if (root.view === "month") {
                    viewLoader.item.showMonth(U.addMonths(shownMonth, dir), false)
                    return
                }
                if (root.view === "week") cursor = U.addDays(cursor, 7 * dir)
                else if (root.view === "day") cursor = U.addDays(cursor, dir)
                else cursor = U.addDays(cursor, 7 * dir)
                slideIn(dir)
            }

            // open one day from another view; the header then offers a way back
            property string backTo: ""
            function openDay(d) {
                if (root.view !== "day") backTo = root.view
                cursor = d
                root.view = "day"
            }
            function goBack() {
                const v = backTo
                backTo = ""
                root.view = v || "month"
            }

            function goToday() {
                const t = U.dayStart(new Date())
                const dir = t < cursor ? -1 : t > cursor ? 1 : 0
                cursor = t
                if (root.view === "month") viewLoader.item.showMonth(t, false)
                else if (dir !== 0) slideIn(dir)
            }

            // the month the month view is scrolled to (title, subtitle)
            readonly property date shownMonth: root.view === "month" && viewLoader.item?.shownMonth
                ? viewLoader.item.shownMonth : U.monthStart(cursor)

            // switching views slides too, in the order of the buttons
            // (day · week · month · agenda): a view to the right comes in from the right
            readonly property var viewOrder: ["day", "week", "month", "agenda"]
            property string lastView: root.view
            Connections {
                target: root
                function onViewChanged() {
                    const dir = Math.sign(win.viewOrder.indexOf(root.view) - win.viewOrder.indexOf(win.lastView))
                    win.lastView = root.view
                    if (dir !== 0) Qt.callLater(win.slideIn, dir)     // once the new view is built
                }
            }

            // is today in what's shown? (the Today buttons are dimmed when not)
            readonly property bool showingToday: {
                const t = new Date()
                if (root.view === "week") return U.sameDay(U.weekStart(cursor), U.weekStart(t))
                if (root.view === "month") return U.sameDay(shownMonth, U.monthStart(t))
                return U.isToday(cursor)
            }

            // content slides in from the side we're going to
            function slideIn(dir) {
                viewIn.stop()                    // no fade/zoom mixed into the slide
                viewLoader.opacity = 1
                viewLoader.scale = 1
                slide.stop()
                slideX.from = dir * 46
                slide.start()
            }
            ParallelAnimation {
                id: slide
                NumberAnimation { id: slideX; target: viewShift; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: viewHost; property: "opacity"; from: 0.25; to: 1; duration: 220; easing.type: Easing.OutCubic }
            }

            function newEvent(start, allDay, end) {
                if (CalendarStore.writableCalendars.length === 0) { accountDialog.start(); return }
                if (!start) {
                    const d = new Date(cursor)
                    const now = new Date()
                    d.setHours(U.sameDay(d, now) ? now.getHours() + 1 : 9, 0, 0, 0)
                    start = d
                }
                eventDialog.create(start, !!allDay, end)
            }

            readonly property string heading: {
                const c = cursor
                if (root.view === "month") return U.monthNames[shownMonth.getMonth()] + " " + shownMonth.getFullYear()
                if (root.view === "day") return U.fmtDate(c)
                if (root.view === "agenda") return "Upcoming"
                const s = U.weekStart(c), e = U.addDays(s, 6)
                return s.getMonth() === e.getMonth()
                    ? s.getDate() + " – " + e.getDate() + " " + U.monthNames[s.getMonth()] + " " + e.getFullYear()
                    : s.getDate() + " " + U.monthNames[s.getMonth()].slice(0, 3) + " – " + e.getDate() + " " + U.monthNames[e.getMonth()].slice(0, 3) + " " + e.getFullYear()
            }
            readonly property string subtitle: {
                if (root.view === "agenda") return "Next 60 days from " + U.fmtShortDate(cursor)
                if (root.view === "day") {
                    const n = CalendarStore.eventsOn(cursor).length
                    return (U.isToday(cursor) ? "Today  ·  " : "") + (n === 0 ? "Nothing planned" : n + (n === 1 ? " event" : " events"))
                }
                return "Week " + U.weekNumber(root.view === "month" ? shownMonth : cursor)
                     + (root.view === "month" ? " – " + U.weekNumber(U.addDays(U.addMonths(shownMonth, 1), -1)) + "  ·  scroll for more" : "")
            }

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: NiriSettings.appRadius          // same corners as niri's windows
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.86)
                // no own border: niri draws the window's border, and one inside got
                // clipped at the rounded corners (looked cut off when resizing)

                // keyboard shortcuts (inactive while typing in a dialog)
                Item {
                    id: keys
                    focus: true
                    Keys.onPressed: event => {
                        if (eventDialog.shown || accountDialog.shown || calSettings.shown || scopeDialog.shown) return
                        switch (event.key) {
                        case Qt.Key_Left: win.step(-1); break
                        case Qt.Key_Right: win.step(1); break
                        case Qt.Key_T: win.goToday(); break
                        case Qt.Key_N: win.newEvent(); break
                        case Qt.Key_1: win.backTo = ""; root.view = "day"; break
                        case Qt.Key_2: win.backTo = ""; root.view = "week"; break
                        case Qt.Key_3: win.backTo = ""; root.view = "month"; break
                        case Qt.Key_4: win.backTo = ""; root.view = "agenda"; break
                        case Qt.Key_Backspace:
                        case Qt.Key_Escape: if (win.backTo === "") return; win.goBack(); break
                        default: return
                        }
                        event.accepted = true
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    // ── Sidebar ───────────────────────────────────────────────
                    Rectangle {
                        Layout.preferredWidth: 260
                        Layout.fillHeight: true
                        radius: Math.max(6, NiriSettings.appRadius - 2)
                        color: "#27000000"
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            // title / drag handle
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 10
                                    Text {
                                        text: "󰃭"
                                        color: Colors.color6
                                        font.pixelSize: 22
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Calendar"
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                }
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) bg.Window.window.startSystemMove()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                ActionButton {
                                    Layout.fillWidth: true
                                    implicitHeight: Properties.buttonHeight + 4
                                    icon: "󰐕"
                                    text: "New event"
                                    primary: true
                                    onClicked: win.newEvent()
                                }
                                ActionButton {
                                    implicitHeight: Properties.buttonHeight + 4
                                    icon: "󰃶"
                                    text: "Today"
                                    opacity: win.showingToday ? 1 : 0.45
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    onClicked: win.goToday()
                                }
                            }

                            MiniMonth {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                selected: win.cursor
                                onPicked: d => {
                                    const dir = d < win.cursor ? -1 : d > win.cursor ? 1 : 0
                                    win.cursor = d
                                    if (root.view !== "month" && dir !== 0) win.slideIn(dir)
                                }
                            }

                            // calendars
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    text: "CALENDARS"
                                    color: Qt.rgba(1, 1, 1, 0.4)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    font.family: Properties.fontFamily
                                }
                                IconButton {
                                    implicitWidth: 24; implicitHeight: 24
                                    iconSize: 12
                                    icon: "󰐕"
                                    tooltip: "Add account"
                                    onClicked: accountDialog.start()
                                }
                            }

                            // 4 px wider than the column on each side, list inset by the same:
                            // same look, but hover-grown buttons at the edge aren't clipped
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: -4
                                Layout.rightMargin: -4
                                contentHeight: accCol.implicitHeight + 8
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: accCol
                                    x: 4
                                    y: 4
                                    width: parent.width - 8
                                    spacing: 8

                                    // empty state
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: CalendarStore.accounts.length === 0
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 4
                                            text: "No calendars yet. Add iCloud, a CalDAV server, a Google / Outlook link or a local calendar."
                                            color: Qt.rgba(1, 1, 1, 0.45)
                                            font.pixelSize: 11
                                            font.family: Properties.fontFamily
                                            wrapMode: Text.WordWrap
                                        }
                                        ActionButton {
                                            icon: "󰐕"
                                            text: "Add account"
                                            onClicked: accountDialog.start()
                                        }
                                    }

                                    Repeater {
                                        model: CalendarStore.accounts
                                        AccountGroup {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            account: modelData
                                        }
                                    }
                                }
                            }

                            // sync status
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    readonly property int errs: CalendarStore.errors.length
                                    text: CalendarStore.syncing ? "Syncing…"
                                        : errs > 0 ? "󰀦  " + errs + (errs === 1 ? " calendar" : " calendars") + " couldn't sync"
                                        : CalendarStore.lastSync > 0 ? "Synced " + Qt.formatTime(new Date(CalendarStore.lastSync), "HH:mm") : ""
                                    color: errs > 0 && !CalendarStore.syncing ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.4)
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                    HoverHandler { id: errHover }
                                    ToolTip.visible: errHover.hovered && errs > 0
                                    ToolTip.text: CalendarStore.errors.map(e => (e.account ? e.account + ": " : "") + e.message).join("\n")
                                }
                                IconButton {
                                    implicitWidth: 26; implicitHeight: 26
                                    iconSize: 12
                                    icon: "󰑐"
                                    tooltip: "Sync now"
                                    interactive: !CalendarStore.syncing && CalendarStore.accounts.length > 0
                                    rotation: CalendarStore.syncing ? 360 : 0
                                    RotationAnimation on rotation {
                                        running: CalendarStore.syncing
                                        loops: Animation.Infinite
                                        from: 0; to: 360; duration: 900
                                    }
                                    onClicked: CalendarStore.sync()
                                }
                            }
                        }
                    }

                    // ── Content ───────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // header (drag handle too)
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 56
                            DragHandler {
                                target: null
                                onActiveChanged: if (active) bg.Window.window.startSystemMove()
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: win.heading
                                        color: "white"
                                        font.pixelSize: 24
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: win.subtitle
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: 12
                                        font.family: Properties.fontFamily
                                    }
                                }

                                ActionButton {
                                    text: "Today"
                                    primary: win.showingToday
                                    opacity: win.showingToday ? 1 : 0.45
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    onClicked: win.goToday()
                                }
                                IconButton {
                                    icon: "󰅁"
                                    tooltip: "Previous  (←)"
                                    onClicked: win.step(-1)
                                }
                                IconButton {
                                    icon: "󰅂"
                                    tooltip: "Next  (→)"
                                    onClicked: win.step(1)
                                }
                                Item { Layout.preferredWidth: 6 }
                                // back to the view the day was opened from
                                ActionButton {
                                    visible: win.backTo !== "" && root.view === "day"
                                    icon: "󰁍"
                                    text: "Back to " + win.backTo
                                    onClicked: win.goBack()
                                }
                                ChoiceControl {
                                    options: ["day", "week", "month", "agenda"]
                                    value: root.view
                                    onEdited: v => { win.backTo = ""; root.view = v }
                                }
                                Item { Layout.preferredWidth: 6 }
                                IconButton {
                                    icon: "󰒓"
                                    tooltip: "Calendar settings"
                                    onClicked: calSettings.open()
                                }
                                IconButton {
                                    icon: "󰅖"
                                    tooltip: "Close"
                                    onClicked: root.open = false
                                }
                            }
                        }

                        Item {
                            id: viewHost
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Item {
                                id: viewShift
                                width: parent.width
                                height: parent.height
                                Loader {
                                    id: viewLoader
                                    anchors.fill: parent
                                    sourceComponent: root.view === "month" ? monthView
                                                   : root.view === "agenda" ? agendaView : timeView
                                    // only the first view when the window opens fades + settles in;
                                    // switching views only slides (onViewChanged), never both
                                    property bool first: true
                                    onLoaded: if (first) { first = false; viewIn.restart() }
                                }
                            }
                            ParallelAnimation {
                                id: viewIn
                                NumberAnimation { target: viewLoader; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: viewLoader; property: "scale"; from: 0.985; to: 1; duration: 260; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                EventDialog { id: eventDialog; onClosed: keys.forceActiveFocus() }
                AccountDialog { id: accountDialog; onClosed: keys.forceActiveFocus() }
                CalendarSettings { id: calSettings; onClosed: keys.forceActiveFocus() }
                ScopeDialog { id: scopeDialog; onClosed: keys.forceActiveFocus() }

                // writing errors that happen outside a dialog (e.g. keyring)
                Rectangle {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 20 }
                    visible: CalendarStore.lastError !== "" && !eventDialog.shown && !accountDialog.shown && !calSettings.shown
                    width: Math.min(errText.implicitWidth + 50, parent.width - 80)
                    height: 40
                    radius: 20
                    color: Qt.rgba(0.2, 0.05, 0.08, 0.95)
                    border.width: 1
                    border.color: "#f38ba8"
                    Text {
                        id: errText
                        anchors.centerIn: parent
                        width: parent.width - 40
                        text: CalendarStore.lastError
                        color: "white"
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                    MouseArea { anchors.fill: parent; onClicked: CalendarStore.lastError = "" }
                }
            }

            Component {
                id: monthView
                MonthView {
                    cursor: win.cursor
                    onDaySelected: d => win.cursor = d
                    onDayOpened: d => win.openDay(d)
                    onEventClicked: ev => eventDialog.showEvent(ev)
                    onCreateAt: (start, allDay) => win.newEvent(start, allDay)
                }
            }
            Component {
                id: timeView
                TimeGridView {
                    days: root.view === "day" ? 1 : 7
                    start: root.view === "day" ? win.cursor : U.weekStart(win.cursor)
                    cursor: win.cursor
                    onDaySelected: d => win.cursor = d
                    onDayOpened: d => win.openDay(d)
                    onEventClicked: ev => eventDialog.showEvent(ev)
                    onCreateAt: (start, allDay) => win.newEvent(start, allDay)
                    onCreateRange: (start, end) => win.newEvent(new Date(start), false, new Date(end))
                    onEventMoved: (ev, start, end) => ev.recurring ? scopeDialog.ask(ev, start, end)
                                                                   : CalendarStore.moveEvent(ev, start, end)
                }
            }
            Component {
                id: agendaView
                AgendaView {
                    cursor: win.cursor
                    onEventClicked: ev => eventDialog.showEvent(ev)
                    onDayOpened: d => win.openDay(d)
                }
            }
        }
    }
}
