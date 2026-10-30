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
// Keys: ←/→ previous/next · T today · N new event · I import · 1-4 day/week/month/agenda
//       Ctrl +/-/0 (or Ctrl + wheel) zoom the whole window (AppZoom)
//       Ctrl Alt +/-/0 (or Ctrl + wheel over the hours) zoom the day / week view
// .ics files: drop them on the window, or  qs ipc call calendar importFile <path>
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
    // moved events wait a few seconds before they're saved: closing doesn't wait
    onOpenChanged: if (!open) { CalendarStore.flushMoves(); CalendarStore.clearSelection() }

    // what the IPC target and the rest of the shell (Panels.call("calendar", …)) can do
    function toggleWindow() { if (!root.open) root.resetView(); root.open = !root.open }
    function openWindow() { if (!root.open) root.resetView(); root.show() }
    // that day in the day view, e.g. "2026-10-16" (reminder notifications, dashboard)
    function goToDate(date) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
        if (m) root.jumpTo = new Date(+m[1], +m[2] - 1, +m[3])
        if (root.view === "month" || root.view === "agenda") root.view = "day"
        root.show()
    }
    // new event on that day (the dashboard's right-click uses it)
    function newEventOn(date) {
        const d = root.parseDay(date)
        if (d) { root.pendingNew = true; root.jumpTo = d }     // flag first: the guard sees it
        if (!root.open) root.resetView()
        root.show()
    }
    function newEventDraft(d) {
        if (!d || !d.start) return
        const day = new Date(d.start); day.setHours(0, 0, 0, 0)
        root.pendingDraft = d
        root.pendingNew = true
        root.jumpTo = day
        if (!root.open) root.resetView()
        root.show()
    }
    // details of one event (id from CalendarStore), e.g. from the dashboard
    function showEventId(id) {
        const e = CalendarStore.visibleEvents.find(x => x.id === id)
        if (e) { const d = new Date(e.start); d.setHours(0, 0, 0, 0); root.pendingEvent = id; root.jumpTo = d }
        if (!root.open) root.resetView()
        root.show()
    }
    // import dialog for that .ics file (file managers: the .desktop entry's MimeType)
    function importPath(path) {
        if (path) root.pendingImport = [path]
        if (!root.open) root.resetView()
        root.show()
    }
    function switchView(view) {
        if (["day", "week", "month", "agenda"].includes(view)) root.view = view
        root.show()
    }

    readonly property var api: ({
        toggle: () => root.toggleWindow(),
        open: () => root.openWindow(),
        close: () => root.open = false,
        openDate: date => root.goToDate(date),
        newEvent: date => root.newEventOn(date),
        // a new event filled in: { title, start, end, allDay, location, description } (ms; e.g. a date in a mail)
        newEventWith: draft => root.newEventDraft(draft),
        showEvent: id => root.showEventId(id),
        setView: view => root.switchView(view),
        importFile: path => root.importPath(path),
        settings: page => root.openDialog("settings" + (page ? ":" + page : "")),
        addAccount: () => root.openDialog("addAccount"),
        transfer: mode => root.openDialog(mode === "import" ? "import" : "export"),
        importAccounts: path => root.openDialog("importfile:" + path)
    })
    Component.onCompleted: Panels.register("calendar", api)
    Component.onDestruction: Panels.unregister("calendar", api)

    IpcHandler {
        target: "calendar"
        function toggle(): void { root.toggleWindow() }
        function open(): void { root.openWindow() }
        function close(): void { root.open = false }
        // e.g. qs ipc call calendar setView week   ("show" clashes with `qs ipc show`)
        // e.g. qs ipc call calendar openDate 2026-10-16   (reminder notifications use it)
        function openDate(date: string): void { root.goToDate(date) }
        function newEvent(date: string): void { root.newEventOn(date) }
        function showEvent(id: string): void { root.showEventId(id) }
        function setView(view: string): void { root.switchView(view) }
        function importFile(path: string): void { root.importPath(path) }
    }

    readonly property string windowTitle: "Quickshell Calendar"

    // open, or bring the already open window to the front (the compositor
    // focuses it, switching workspace / monitor if needed)
    function show() {
        if (root.open) Compositor.focusWindow(root.windowTitle)
        root.open = true
    }


    // fresh open: the view picked in the calendar settings
    function resetView() { root.view = Settings.calendar.defaultView ?? "month" }

    // jump the open (or opening) window to a day — set by openDate()
    property var jumpTo: null
    property bool pendingNew: false        // then open the editor there
    property var pendingDraft: null        // … filled in with this (newEventDraft)
    property string pendingEvent: ""       // then show that event
    property var pendingImport: []         // then open the import dialog for these files
    property string pendingDialog: ""      // "settings[:page]" | "addAccount" | "export" | "import" | "importfile:<path>" (the settings app)
    function openDialog(d) {
        if (!root.open) root.resetView()
        root.pendingDialog = d
        root.show()
    }

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
                function onPendingImportChanged() { Qt.callLater(win.takePending) }
                function onPendingDialogChanged() { Qt.callLater(win.takePending) }
            }

            function takePending() {
                if (root.pendingDialog) {
                    const d = root.pendingDialog
                    root.pendingDialog = ""
                    if (eventDialog.shown && eventDialog.editing) eventDialog.shake()
                    else {
                        eventDialog.close(); accountDialog.close(); calSettings.close(); transfer.close()
                        if (d.startsWith("settings")) calSettings.openPage(d.includes(":") ? d.slice(9) : calSettings.page || "reminders")
                        else if (d === "addAccount") accountDialog.start()
                        else if (d.startsWith("importfile:")) transfer.startFile(d.slice(11))
                        else transfer.start(d)
                    }
                }
                // an event being written isn't thrown away for a new request
                if (eventDialog.shown && eventDialog.editing && (root.pendingNew || root.pendingEvent)) {
                    root.jumpTo = null
                    root.pendingNew = false
                    root.pendingDraft = null
                    root.pendingEvent = ""
                    eventDialog.shake()
                    return
                }
                if (root.pendingImport.length > 0) {
                    const p = root.pendingImport
                    root.pendingImport = []
                    if (eventDialog.shown && eventDialog.editing) eventDialog.shake()
                    else { eventDialog.close(); accountDialog.close(); importDialog.openFiles(p) }
                }
                if (root.jumpTo) { cursor = root.jumpTo; root.jumpTo = null }
                if (root.pendingNew) {
                    const d = root.pendingDraft
                    root.pendingNew = false
                    root.pendingDraft = null
                    if (d) newEvent(new Date(d.start), d.allDay, d.end ? new Date(d.end) : null, d)
                    else newEvent()
                }
                if (root.pendingEvent) {
                    const e = CalendarStore.visibleEvents.find(x => x.id === root.pendingEvent)
                    root.pendingEvent = ""
                    if (e) eventDialog.showEvent(e)
                }
            }

            Component.onCompleted: {
                Qt.callLater(takePending)       // once the dialogs exist
                CalendarStore.ensureRange(cursor)
                if (Date.now() - CalendarStore.lastSync > 60000) CalendarStore.sync(true)
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
            readonly property bool timeGrid: root.view === "day" || root.view === "week"
            function zoom(dir) { if (timeGrid && typeof viewLoader.item?.zoom === "function") viewLoader.item.zoom(dir) }
            property string lastView: root.view
            Connections {
                target: root
                // the new view starts hidden and shifted right away (no frame of it
                // standing still first); the slide runs once it's built (the
                // Loader builds it synchronously, callLater comes after that)
                function onViewChanged() {
                    const dir = Math.sign(win.viewOrder.indexOf(root.view) - win.viewOrder.indexOf(win.lastView))
                    win.lastView = root.view
                    if (dir === 0) return
                    win.prepareSlide(dir)
                    Qt.callLater(win.runSlide)
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
            function prepareSlide(dir, fromOpacity) {
                viewIn.stop()                    // no fade/zoom mixed into the slide
                slide.stop()
                viewLoader.opacity = 1
                viewLoader.scale = 1
                viewShift.x = dir * 40
                viewHost.opacity = fromOpacity ?? 0
            }
            function runSlide() {
                slideX.from = viewShift.x
                slideO.from = viewHost.opacity
                slide.restart()
            }
            // prev / next: the same view, other dates
            function slideIn(dir) { prepareSlide(dir, 0.25); runSlide() }
            ParallelAnimation {
                id: slide
                NumberAnimation { id: slideX; target: viewShift; property: "x"; to: 0; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { id: slideO; target: viewHost; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            }

            // ── several selected events (SelectionBar) ──
            function openEvent(ev) { CalendarStore.clearSelection(); eventDialog.showEvent(ev) }
            function shiftedEv(ev, dMin, dDay) {
                const s = new Date(ev.start); s.setDate(s.getDate() + dDay); s.setMinutes(s.getMinutes() + dMin)
                const e = new Date(ev.end); e.setDate(e.getDate() + dDay); e.setMinutes(e.getMinutes() + dMin)
                return { ev: ev, start: s.getTime(), end: e.getTime() }
            }
            // all selected (writable) ones by the same amount; repeating ones: asked once
            function groupMove(dMin, dDay) {
                const moves = CalendarStore.selectedEvents.filter(e => !(CalendarStore.calendarMap[e.calendar]?.readOnly ?? true))
                                                          .map(e => shiftedEv(e, dMin, dDay))
                const main = moves.find(m => m.ev.recurring)
                if (main) scopeDialog.ask(main.ev, main.start, main.end, moves.filter(m => m !== main))
                else for (const m of moves) CalendarStore.moveEvent(m.ev, m.start, m.end)
            }
            function deleteSelection(onlyThis) {
                const list = CalendarStore.selectedEvents.filter(e => !(CalendarStore.calendarMap[e.calendar]?.readOnly ?? true))
                CalendarStore.clearSelection()
                CalendarStore.deleteMany(list, onlyThis, () => {
                    // my invitations: the guests get a cancellation (like deleting one in the dialog)
                    const sent = {}
                    for (const e of list) {
                        if ((onlyThis && e.recurring) || !(e.attendees ?? []).length || sent[e.uid]) continue
                        if (CalendarStore.calendarMap[e.calendar]?.accountType === "graph") continue
                        const org = (e.organizer?.email ?? "").toLowerCase()
                        const acc = MailStore.activeAccounts.find(a => a.email.toLowerCase() === org)
                        if (!acc) continue
                        sent[e.uid] = true
                        MailStore.sendInvite(acc.id, { uid: e.uid, title: e.title, start: e.start, end: e.end, allDay: e.allDay,
                                                       location: e.location, sequence: (e.sequence ?? 0) + 1, attendees: e.attendees,
                                                       rrule: e.rrule ?? "" }, "CANCEL", r => { if (!r.ok) CalendarStore.lastError = "Cancellation not sent: " + r.error })
                    }
                })
            }

            function newEvent(start, allDay, end, draft) {
                if (CalendarStore.writableCalendars.length === 0) { accountDialog.start(); return }
                if (!start) {
                    const d = new Date(cursor)
                    const now = new Date()
                    d.setHours(U.sameDay(d, now) ? now.getHours() + 1 : 9, 0, 0, 0)
                    start = d
                }
                eventDialog.create(start, !!allDay, end, draft)
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

            // Ctrl +/−/0, Ctrl + wheel: the whole window bigger or smaller (AppZoom)
            ZoomArea {
                id: zoomArea
                app: "calendar"
                anchors.fill: parent
                // Ctrl + wheel over the hours zooms them, not the window
                wheelExcept: [viewLoader.item?.hourGrid ?? null]
                Rectangle {
                    id: bg
                    anchors.fill: parent
                    radius: Compositor.appRadius / zoomArea.zoom          // same corners as the compositor's windows
                    color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.86)
                    // no own border: the compositor draws the window's border, and one inside got
                    // clipped at the rounded corners (looked cut off when resizing)

                    // keyboard shortcuts (inactive while typing in a dialog)
                    Item {
                        id: keys
                        focus: true
                        Keys.onPressed: event => {
                            if (eventDialog.shown || accountDialog.shown || calSettings.shown || scopeDialog.shown || importDialog.shown || transfer.shown) return
                            // Ctrl +/−/0 alone zooms the whole window (ZoomArea); with Alt the hours
                            if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.AltModifier)) {
                                const z = event.key === Qt.Key_Plus || event.key === Qt.Key_Equal ? 1
                                        : event.key === Qt.Key_Minus ? -1 : event.key === Qt.Key_0 ? 0 : null
                                if (z === null || !win.timeGrid) return
                                win.zoom(z)
                                event.accepted = true
                                return
                            }
                            switch (event.key) {
                            case Qt.Key_Left: win.step(-1); break
                            case Qt.Key_Right: win.step(1); break
                            case Qt.Key_T: win.goToday(); break
                            case Qt.Key_N: win.newEvent(); break
                            case Qt.Key_I: importDialog.pick(); break
                            case Qt.Key_1: win.backTo = ""; root.view = "day"; break
                            case Qt.Key_2: win.backTo = ""; root.view = "week"; break
                            case Qt.Key_3: win.backTo = ""; root.view = "month"; break
                            case Qt.Key_4: win.backTo = ""; root.view = "agenda"; break
                            case Qt.Key_Delete: if (CalendarStore.selectedCount === 0) return; selBar.confirming = true; break
                            case Qt.Key_Escape:
                                if (selBar.confirming) { selBar.confirming = false; break }
                                if (CalendarStore.selectedCount > 0) { CalendarStore.clearSelection(); break }
                                if (win.backTo === "") return; win.goBack(); break
                            case Qt.Key_Backspace: if (win.backTo === "") return; win.goBack(); break
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
                            radius: Math.max(6, Compositor.appRadius - 2)
                            color: Colors.card
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
                                            color: Colors.ink
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
                                        interactive: !win.showingToday
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
                                        color: Colors.fade(0.4)
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 1.2
                                        font.family: Properties.fontFamily
                                    }
                                    IconButton {
                                        implicitWidth: 24; implicitHeight: 24
                                        iconSize: 12
                                        icon: "󰋺"
                                        tooltip: "Import .ics file  (I)"
                                        onClicked: importDialog.pick()
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
                                                text: "No calendars yet. Add iCloud, a CalDAV server, a Google / Outlook link or a local calendar — or import an .ics export."
                                                color: Colors.fade(0.45)
                                                font.pixelSize: 11
                                                font.family: Properties.fontFamily
                                                wrapMode: Text.WordWrap
                                            }
                                            RowLayout {
                                                spacing: 6
                                                ActionButton {
                                                    icon: "󰐕"
                                                    text: "Add account"
                                                    onClicked: accountDialog.start()
                                                }
                                                ActionButton {
                                                    icon: "󰋺"
                                                    text: "Import"
                                                    onClicked: importDialog.pick()
                                                }
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
                                        color: errs > 0 && !CalendarStore.syncing ? Colors.red : Colors.fade(0.4)
                                        font.pixelSize: 10
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                        HoverHandler { id: errHover }
                                        ToolTip.visible: errHover.hovered && errs > 0
                                        ToolTip.text: CalendarStore.errors.map(e => (e.account ? e.account + ": " : "") + e.message).join("\n")
                                    }
                                    // settings next to sync, like the mail app
                                    IconButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        iconSize: 12
                                        icon: "󰒓"
                                        tooltip: "Calendar settings"
                                        onClicked: calSettings.open()
                                    }
                                    IconButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        iconSize: 12
                                        icon: "󰑐"
                                        tooltip: "Sync now"
                                        interactive: !CalendarStore.syncing && CalendarStore.activeAccounts.length > 0
                                        rotation: CalendarStore.syncing ? 360 : 0
                                        RotationAnimation on rotation {
                                            running: CalendarStore.syncing
                                            loops: Animation.Infinite
                                            from: 0; to: 360; duration: 900
                                        }
                                        onClicked: CalendarStore.sync(true)
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
                                            color: Colors.ink
                                            font.pixelSize: 24
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: win.subtitle
                                            color: Colors.fade(0.5)
                                            font.pixelSize: 12
                                            font.family: Properties.fontFamily
                                        }
                                    }

                                    // greyed out while today is already shown (clicking would do nothing)
                                    ActionButton {
                                        text: "Today"
                                        interactive: !win.showingToday
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
                                    // zoom of the day / week view
                                    RowLayout {
                                        visible: win.timeGrid
                                        spacing: 0
                                        IconButton {
                                            implicitWidth: 26; implicitHeight: 26
                                            iconSize: 11
                                            icon: "󰍴"
                                            tooltip: "Zoom out the hours  (Ctrl Alt −, Ctrl + wheel over them) · " + CalendarStore.zoom + "%"
                                            interactive: CalendarStore.zoom > CalendarStore.zoomSteps[0]
                                            onClicked: win.zoom(-1)
                                        }
                                        Text {
                                            visible: CalendarStore.zoom !== 100
                                            Layout.preferredWidth: 38
                                            horizontalAlignment: Text.AlignHCenter
                                            text: CalendarStore.zoom + "%"
                                            color: Colors.fade(CalendarStore.zoom === 100 ? 0.4 : 0.75)
                                            font.pixelSize: 11
                                            font.family: Properties.fontFamily
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.zoom(0)
                                            }
                                        }
                                        IconButton {
                                            implicitWidth: 26; implicitHeight: 26
                                            iconSize: 11
                                            icon: "󰐕"
                                            tooltip: "Zoom in the hours  (Ctrl Alt +) · " + CalendarStore.zoom + "%"
                                            interactive: CalendarStore.zoom < CalendarStore.zoomSteps[CalendarStore.zoomSteps.length - 1]
                                            onClicked: win.zoom(1)
                                        }
                                    }
                                    ChoiceControl {
                                        navStyle: true
                                        options: ["day", "week", "month", "agenda"]
                                        value: root.view
                                        onEdited: v => { win.backTo = ""; root.view = v }
                                    }
                                    Item { Layout.preferredWidth: 6 }
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
                    CalendarSettings {
                        id: calSettings
                        onClosed: keys.forceActiveFocus()
                        onAddAccount: accountDialog.start()
                        onTransfer: mode => transfer.start(mode)
                    }
                    CalendarTransfer { id: transfer; onClosed: keys.forceActiveFocus() }
                    ScopeDialog { id: scopeDialog; onClosed: keys.forceActiveFocus() }
                    ImportDialog {
                        id: importDialog
                        onClosed: keys.forceActiveFocus()
                        onShowDate: d => { win.cursor = d; if (root.view === "month") viewLoader.item.showMonth(d, false) }
                    }

                    // drop .ics files (Apple / Google / Outlook exports, invites) anywhere on the window
                    DropArea {
                        id: drop
                        anchors.fill: parent
                        keys: ["text/uri-list"]
                        onEntered: drag => drag.accepted = drag.hasUrls
                        onDropped: drop => {
                            const p = drop.urls.map(u => String(u)).filter(u => u.startsWith("file://"))
                            if (p.length > 0) { root.pendingImport = p; drop.accept() }
                        }
                    }
                    DropZone {
                        anchors.fill: parent
                        anchors.margins: 10
                        radius: Math.max(6, Compositor.appRadius - 4)
                        shown: drop.containsDrag
                        hot: true
                        z: 200
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰋺"
                                color: Colors.color6
                                font.pixelSize: 40
                                font.family: Properties.fontFamily
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Drop to import"
                                color: Colors.ink
                                font.pixelSize: 16
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ".ics exports from Apple Calendar, Google, Outlook, … or a single invite"
                                color: Colors.fade(0.55)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                        }
                    }

                    SelectionBar {
                        id: selBar
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 20 }
                        z: 50
                        onShiftDays: n => win.groupMove(0, n)
                        onDeleteAll: onlyThis => win.deleteSelection(onlyThis)
                        onMoveTo: calId => { const l = CalendarStore.selectedEvents; CalendarStore.clearSelection(); CalendarStore.moveManyTo(l, calId) }
                        onDuplicate: { const l = CalendarStore.selectedEvents; CalendarStore.clearSelection(); CalendarStore.duplicateMany(l, 0) }
                    }

                    // writing errors that happen outside a dialog (e.g. keyring)
                    Rectangle {
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: selBar.shown ? 84 : 20 }
                        visible: CalendarStore.lastError !== "" && !eventDialog.shown && !accountDialog.shown && !calSettings.shown && !importDialog.shown && !transfer.shown
                        width: Math.min(errText.implicitWidth + 50, parent.width - 80)
                        height: 40
                        radius: 20
                        color: Qt.rgba(0.2, 0.05, 0.08, 0.95)
                        border.width: 1
                        border.color: Colors.red
                        Text {
                            id: errText
                            anchors.centerIn: parent
                            width: parent.width - 40
                            text: CalendarStore.lastError
                            color: Colors.ink
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        MouseArea { anchors.fill: parent; onClicked: CalendarStore.lastError = "" }
                    }
                }
            }

            Component {
                id: monthView
                MonthView {
                    cursor: win.cursor
                    onDaySelected: d => win.cursor = d
                    onDayOpened: d => win.openDay(d)
                    onEventClicked: ev => win.openEvent(ev)
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
                    onEventClicked: ev => win.openEvent(ev)
                    onCreateAt: (start, allDay) => win.newEvent(start, allDay)
                    onCreateRange: (start, end) => win.newEvent(new Date(start), false, new Date(end))
                    onEventMoved: (ev, start, end) => ev.recurring ? scopeDialog.ask(ev, start, end)
                                                                   : CalendarStore.moveEvent(ev, start, end)
                    onGroupMoved: (dMin, dDay) => win.groupMove(dMin, dDay)
                }
            }
            Component {
                id: agendaView
                AgendaView {
                    cursor: win.cursor
                    onEventClicked: ev => win.openEvent(ev)
                    onDayOpened: d => win.openDay(d)
                }
            }
        }
    }
}
