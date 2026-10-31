import QtQuick
import QtQuick.Layouts
import qs.services
import "CalUtil.js" as U

// Month view as an endless list of weeks: scroll (wheel / drag) through the
// year, it settles on a week; six weeks fill the view. `shownMonth` is the
// month in the middle of the view — the window uses it for the title.
// Click a day to select it, double-click to add an event, "+N more" / the
// day number opens the day.
ColumnLayout {
    id: root

    property date cursor: new Date()
    signal daySelected(date day)
    signal dayOpened(date day)
    signal eventClicked(var ev, Item item)
    signal createAt(date start, bool allDay)

    readonly property bool weekNumbers: Settings.calendar.weekNumbers ?? true

    // week 0 = the week of 5 Jan 1970; enough weeks for ±80 years
    readonly property date origin: U.weekStart(new Date(1970, 0, 5))
    readonly property int weekCount: 52 * 160
    function weekIndex(d) { return Math.round((U.weekStart(d).getTime() - origin.getTime()) / (7 * 86400000)) }
    function weekDate(i) { return U.addDays(origin, i * 7) }

    // scroll position in weeks (fractional): the week at the top of the view.
    // Eight week rows are reused and placed from it, so the list is endless
    // and exact (no estimated content height like a ListView of 8000 rows).
    property real pos: weekIndex(U.monthStart(cursor))
    readonly property real rowH: Math.max(60, viewport.height / 6)
    readonly property int topIndex: Math.round(pos)
    // the month most of the view shows: Thursday of the middle week
    readonly property date shownMonth: U.monthStart(U.addDays(weekDate(topIndex + 2), 3))

    function scrollTo(p, instant) {
        p = Math.max(0, Math.min(weekCount - 6, p))
        scrollAnim.stop()
        if (instant) pos = p
        else { scrollAnim.to = p; scrollAnim.start() }
    }
    // scroll so `day`'s month starts at the top
    function showMonth(day, instant) { scrollTo(weekIndex(U.monthStart(day)), instant) }
    // keep a picked day in view
    function reveal(day) {
        const i = weekIndex(day)
        if (i < topIndex || i > topIndex + 5) showMonth(day, false)
    }

    NumberAnimation {
        id: scrollAnim
        target: root
        property: "pos"
        duration: Anim.slow
        easing.type: Anim.standard
    }

    onCursorChanged: reveal(cursor)
    onShownMonthChanged: CalendarStore.ensureRange(shownMonth)

    spacing: Tokens.space.s6

    // weekday header
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root.weekNumbers ? 34 : 0
        Layout.rightMargin: Tokens.space.s6
        spacing: Tokens.space.s6
        Repeater {
            model: U.dayShort
            Text {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                leftPadding: Tokens.space.s8
                text: modelData
                color: index >= 5 ? Colors.fade(0.35) : Colors.fade(0.5)
                font.pixelSize: Tokens.font.caption
                font.bold: true
                font.family: Properties.fontFamily
            }
        }
    }

    Item {
        id: viewport
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        Component.onCompleted: root.showMonth(root.cursor, true)

        // wheel: one week per notch, smoothly
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const base = scrollAnim.running ? scrollAnim.to : root.pos
                const steps = event.angleDelta.y !== 0 ? -event.angleDelta.y / 120 : -event.pixelDelta.y / root.rowH
                root.scrollTo(Math.round(base + steps), false)
            }
        }
        // drag the weeks; let go and it settles on a whole week (with a bit of fling)
        DragHandler {
            target: null
            yAxis.enabled: true
            xAxis.enabled: false
            property real startPos: 0
            onActiveChanged: {
                if (active) { scrollAnim.stop(); startPos = root.pos }
                else root.scrollTo(Math.round(root.pos - centroid.velocity.y / root.rowH * 0.25), false)
            }
            onTranslationChanged: if (active) root.pos = Math.max(0, startPos - translation.y / root.rowH)
        }

        Repeater {
            model: 8           // 6 visible + 2 coming in while scrolling
        Item {
            id: week
            required property int index
            // each row keeps its week while scrolling; only the one leaving the
            // top is reused at the bottom (no highlight jumping between rows)
            readonly property int base: Math.floor(root.pos)
            readonly property int weekNo: base + (((index - base) % 8) + 8) % 8
            readonly property date start: root.weekDate(weekNo)
            y: (weekNo - root.pos) * root.rowH
            width: viewport.width
            height: root.rowH

            RowLayout {
                anchors.fill: parent
                anchors.rightMargin: Tokens.space.s6
                anchors.bottomMargin: Tokens.space.s6
                spacing: Tokens.space.s6

                // week number
                Text {
                    visible: root.weekNumbers
                    Layout.preferredWidth: 28
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.space.s8
                    horizontalAlignment: Text.AlignRight
                    text: U.weekNumber(week.start)
                    color: Colors.fade(0.25)
                    font.pixelSize: Tokens.font.micro
                    font.family: Properties.fontFamily
                }

                Repeater {
                    model: 7
                    Rectangle {
                        id: cell
                        required property int index
                        readonly property date day: U.addDays(week.start, index)
                        readonly property bool inMonth: day.getMonth() === root.shownMonth.getMonth()
                        readonly property bool today: U.isToday(day)
                        readonly property bool isSel: U.sameDay(day, root.cursor)
                        readonly property bool weekend: index >= 5
                        readonly property var evs: CalendarStore.eventsOn(day).slice().sort((a, b) =>
                            (U.fullDay(b, day) - U.fullDay(a, day)) || a.start - b.start)
                        readonly property int fits: Math.max(0, Math.floor((height - 30) / 22))
                        readonly property int shown: evs.length > fits ? Math.max(0, fits - 1) : evs.length

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: Tokens.radius.xl
                        clip: true
                        // weekend: a shade darker
                        color: isSel ? Colors.fade(0.09)
                             : inMonth ? (weekend ? Colors.shade(0.23) : Colors.card)
                             : (weekend ? Colors.shade(0.13) : Colors.shade(0.08))
                        border.width: Properties.panelBorderWidth
                        border.color: isSel ? Colors.alpha(Colors.color6, 0.6)
                                    : hover.hovered ? Colors.fade(0.16) : Properties.cardBorder
                        Behavior on color { ColorAnimation { duration: Anim.normal } }
                        Behavior on border.color { ColorAnimation { duration: Anim.normal } }

                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: root.daySelected(cell.day)
                            onDoubleTapped: root.createAt(cell.day, true)
                        }

                        // day number (pill on today, "1. Nov" on the first)
                        Rectangle {
                            x: 6; y: 5
                            width: Math.max(22, num.implicitWidth + 12)
                            height: 20
                            radius: Tokens.radius.lg
                            color: cell.today ? Colors.color6 : numHover.hovered ? Colors.fade(0.1) : "transparent"
                            scale: numHover.pressed ? Properties.onPressedButtonScale : numHover.hovered ? Properties.onEnteredButtonScale : 1
                            Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
                            Text {
                                id: num
                                anchors.centerIn: parent
                                text: cell.day.getDate() === 1 ? cell.day.getDate() + ". " + U.monthNames[cell.day.getMonth()].slice(0, 3) : cell.day.getDate()
                                color: cell.today ? U.onColor(Colors.color6)
                                     : cell.inMonth ? (cell.weekend ? Colors.fade(0.6) : Colors.ink) : Colors.fade(0.3)
                                font.pixelSize: Tokens.font.caption
                                font.bold: cell.today || cell.day.getDate() === 1
                                font.family: Properties.fontFamily
                                Behavior on color { ColorAnimation { duration: Anim.normal } }
                            }
                            MouseArea {
                                id: numHover
                                readonly property bool hovered: containsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dayOpened(cell.day)
                            }
                        }

                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5; topMargin: 29 }
                            spacing: Tokens.space.s2
                            opacity: cell.inMonth ? 1 : 0.55
                            Behavior on opacity { NumberAnimation { duration: Anim.normal } }

                            Repeater {
                                model: cell.evs.slice(0, cell.shown)
                                EventChip {
                                    required property var modelData
                                    width: parent.width
                                    ev: modelData
                                    day: cell.day
                                    onClicked: (ev, item) => root.eventClicked(ev, item)
                                }
                            }
                            Text {
                                visible: cell.evs.length > cell.shown
                                leftPadding: Tokens.space.s6
                                text: "+" + (cell.evs.length - cell.shown) + " more"
                                color: moreHover.hovered ? Colors.ink : Colors.fade(0.5)
                                font.pixelSize: Tokens.font.micro
                                font.bold: true
                                font.family: Properties.fontFamily
                                MouseArea {
                                    id: moreHover
                                    readonly property bool hovered: containsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dayOpened(cell.day)
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
