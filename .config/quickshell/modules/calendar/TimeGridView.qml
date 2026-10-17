import QtQuick
import qs.components
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import "CalUtil.js" as U

// Week / day view: all-day row on top, scrollable hour grid below with the
// events side by side where they overlap, and a "now" line.
// Double-click an empty spot to add an event there.
ColumnLayout {
    id: root

    property date start: U.weekStart(new Date())
    property int days: 7
    property date cursor: new Date()
    signal daySelected(date day)
    signal dayOpened(date day)
    signal eventClicked(var ev, Item item)
    signal createAt(date start, bool allDay)
    signal createRange(double start, double end)          // dragged over empty space
    signal eventMoved(var ev, double start, double end)   // dragged / resized

    // y (px in a day column) → minutes since midnight, on 15 min steps
    function snapMin(y) { return Math.max(0, Math.min(24 * 60, Math.round(y / hourHeight * 4) * 15)) }
    // day + minutes → ms (via setHours, so daylight saving days work)
    function at(day, mins) { const d = new Date(day); d.setHours(0, mins, 0, 0); return d.getTime() }
    // ev moved by minutes / days and stretched at the end
    function shifted(ev, dMin, dDay, dEnd) {
        const s = new Date(ev.start); s.setDate(s.getDate() + dDay); s.setMinutes(s.getMinutes() + dMin)
        const e = new Date(ev.end); e.setDate(e.getDate() + dDay); e.setMinutes(e.getMinutes() + dMin + dEnd)
        return Object.assign({}, ev, { start: s.getTime(), end: e.getTime() })
    }

    readonly property int gutter: 52
    readonly property real hourHeight: 52
    readonly property var dayList: {
        const out = []
        for (let i = 0; i < days; i++) out.push(U.addDays(start, i))
        return out
    }

    // minute ticker for the now-line
    property double now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    spacing: 6

    // ── Day headers ──
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root.gutter
        Layout.rightMargin: 8
        spacing: 4
        Repeater {
            model: root.dayList
            Item {
                id: head
                required property var modelData
                readonly property bool today: U.isToday(modelData)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 44

                // centered over its column in the week; day view: on the left, under the title
                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.days === 1 ? 6 : (parent.width - width) / 2
                    spacing: 8
                    Text {
                        text: root.days === 1 ? U.dayNames[U.weekday(head.modelData)] : U.dayShort[U.weekday(head.modelData)]
                        color: head.today ? Colors.color6 : U.weekday(head.modelData) >= 5 ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    Rectangle {
                        implicitWidth: Math.max(30, dnum.implicitWidth + 14)
                        implicitHeight: 30
                        radius: 15
                        color: head.today ? Colors.color6 : dayHover.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        Text {
                            id: dnum
                            anchors.centerIn: parent
                            text: head.modelData.getDate()
                            color: head.today ? U.onColor(Colors.color6) : U.weekday(head.modelData) >= 5 ? Qt.rgba(1, 1, 1, 0.6) : "white"
                            font.pixelSize: 16
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                    }
                }
                HoverHandler { id: dayHover; cursorShape: root.days > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: root.days > 1; onTapped: root.dayOpened(head.modelData) }
            }
        }
    }

    // ── All-day row ──
    Rectangle {
        id: allDay
        Layout.fillWidth: true
        readonly property var perDay: root.dayList.map(d => CalendarStore.eventsOn(d).filter(e => U.fullDay(e, d)))
        readonly property int rows: Math.min(4, Math.max(1, ...perDay.map(l => l.length)))
        readonly property bool any: perDay.some(l => l.length > 0)
        // only there when the shown days have all-day events
        visible: any
        implicitHeight: rows * 22 + 10
        radius: 12
        color: "#27000000"
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        Text {
            width: root.gutter - 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: "all-day"
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 10
            font.family: Properties.fontFamily
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.gutter
            anchors.rightMargin: 8
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            spacing: 4
            Repeater {
                model: root.dayList
                Item {
                    id: adCell
                    required property var modelData
                    required property int index
                    readonly property var evs: allDay.perDay[index] ?? []
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1

                    TapHandler { onDoubleTapped: root.createAt(adCell.modelData, true) }

                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: adCell.evs.slice(0, adCell.evs.length > allDay.rows ? allDay.rows - 1 : allDay.rows)
                            EventChip {
                                required property var modelData
                                width: parent.width
                                ev: modelData
                                day: adCell.modelData
                                onClicked: (ev, item) => root.eventClicked(ev, item)
                            }
                        }
                        Text {
                            visible: adCell.evs.length > allDay.rows
                            leftPadding: 6
                            text: "+" + (adCell.evs.length - allDay.rows + 1) + " more"
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 10
                            font.bold: true
                            font.family: Properties.fontFamily
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dayOpened(adCell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Hour grid ──
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: "#27000000"
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 1
            contentHeight: 24 * root.hourHeight + 16
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: CalScrollBar {}
            SmoothWheel { flick: flick; step: root.hourHeight }      // one hour per notch

            // start at 07:30; if "now" wouldn't be on screen, center on it instead
            function scrollToStart() {
                const n = new Date()
                const nowH = n.getHours() + n.getMinutes() / 60
                const visible = height / root.hourHeight
                let top = parseInt(Settings.calendar.dayStart ?? "7") || 7
                if (nowH > top + visible - 1) top = nowH - visible / 2
                contentY = Math.max(0, Math.min(contentHeight - height, top * root.hourHeight))
            }
            onHeightChanged: if (!scrolled && height > 0) { scrolled = true; scrollToStart() }
            property bool scrolled: false

            Item {
                id: gridArea
                width: flick.width
                height: flick.contentHeight

                // hour lines + labels
                Repeater {
                    model: 24
                    Item {
                        required property int index
                        y: 8 + index * root.hourHeight
                        width: gridArea.width
                        height: root.hourHeight
                        Text {
                            visible: parent.index > 0
                            width: root.gutter - 10
                            y: -height / 2
                            horizontalAlignment: Text.AlignRight
                            text: U.pad(parent.index) + ":00"
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                        }
                        Rectangle {
                            x: root.gutter
                            width: parent.width - root.gutter - 8
                            height: 1
                            color: Qt.rgba(1, 1, 1, parent.index > 0 ? 0.06 : 0)
                        }
                        // half hour
                        Rectangle {
                            x: root.gutter
                            y: root.hourHeight / 2
                            width: parent.width - root.gutter - 8
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.025)
                        }
                    }
                }

                RowLayout {
                    x: root.gutter
                    y: 8
                    width: gridArea.width - root.gutter - 8
                    height: 24 * root.hourHeight
                    spacing: 4

                    Repeater {
                        model: root.dayList
                        Item {
                            id: col
                            required property var modelData
                            required property int index
                            readonly property bool today: U.isToday(modelData)
                            readonly property var items: U.layoutDay(
                                CalendarStore.eventsOn(modelData).filter(e => !U.fullDay(e, modelData)), modelData)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1

                            // line between the days (in the middle of the 4 px gap)
                            Rectangle {
                                visible: root.days > 1 && col.index > 0
                                x: -2.5
                                width: 1
                                height: parent.height
                                color: Qt.rgba(1, 1, 1, 0.09)
                            }

                            // weekend: a shade darker
                            Rectangle {
                                anchors.fill: parent
                                visible: root.days > 1 && U.weekday(col.modelData) >= 5
                                color: "#22000000"
                            }

                            // today tint
                            Rectangle {
                                anchors.fill: parent
                                visible: col.today && root.days > 1
                                radius: 8
                                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.04)
                            }

                            // empty space: click selects the day, double-click adds an
                            // event there, drag down/up to add one for that span
                            MouseArea {
                                id: slots
                                anchors.fill: parent
                                preventStealing: true          // the Flickable would take the drag
                                property real pressY: -1
                                property real curY: -1
                                property bool dragging: false
                                readonly property int fromMin: Math.min(root.snapMin(pressY), root.snapMin(curY))
                                readonly property int toMin: Math.max(Math.max(root.snapMin(pressY), root.snapMin(curY)), fromMin + 15)

                                onPressed: m => { pressY = m.y; curY = m.y; dragging = false }
                                onPositionChanged: m => {
                                    if (!pressed) return
                                    curY = Math.max(0, Math.min(height, m.y))
                                    if (Math.abs(curY - pressY) > 8) dragging = true
                                }
                                onReleased: {
                                    if (dragging) root.createRange(root.at(col.modelData, fromMin), root.at(col.modelData, toMin))
                                    dragging = false
                                    pressY = -1
                                }
                                onClicked: root.daySelected(col.modelData)
                                onDoubleClicked: m => {
                                    const mins = Math.min(Math.floor(m.y / root.hourHeight * 2) * 30, 23 * 60 + 30)
                                    root.createAt(new Date(root.at(col.modelData, mins)), false)
                                }
                            }

                            // the span being drawn
                            Rectangle {
                                visible: slots.dragging
                                x: 2
                                width: parent.width - 4
                                y: slots.fromMin / 60 * root.hourHeight
                                height: (slots.toMin - slots.fromMin) / 60 * root.hourHeight
                                radius: 7
                                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.25)
                                border.width: 1.5
                                border.color: Colors.color6
                                z: 4
                                Text {
                                    anchors { left: parent.left; top: parent.top; margins: 6 }
                                    text: U.pad(Math.floor(slots.fromMin / 60)) + ":" + U.pad(slots.fromMin % 60) + " – "
                                        + U.pad(Math.floor(slots.toMin / 60) % 24) + ":" + U.pad(slots.toMin % 60)
                                    color: "white"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: Properties.fontFamily
                                }
                            }

                            Repeater {
                                model: col.items
                                Rectangle {
                                    id: block
                                    required property var modelData
                                    readonly property var ev: modelData.ev
                                    readonly property color calColor: CalendarStore.calendarMap[ev.calendar]?.color ?? Colors.color6
                                    readonly property bool writable: !(CalendarStore.calendarMap[ev.calendar]?.readOnly ?? true)
                                    readonly property real colW: col.width / modelData.cols

                                    // drag state: minutes moved, days moved (week view), minutes added at the end
                                    property int dMin: 0
                                    property int dDay: 0
                                    property int dEnd: 0
                                    readonly property bool dragging: dMin !== 0 || dDay !== 0 || dEnd !== 0
                                    readonly property var preview: dragging
                                        ? root.shifted(ev, dMin, dDay, dEnd) : ev

                                    x: modelData.col * colW + 1 + dDay * (col.width + 4)
                                    y: (modelData.top + dMin) / 60 * root.hourHeight + 1
                                    width: dragging ? col.width - 2 : colW - 2
                                    height: Math.max(18, (modelData.bottom - modelData.top + dEnd) / 60 * root.hourHeight - 2)
                                    z: dragging ? 10 : 1
                                    radius: 7
                                    clip: true
                                    color: Qt.rgba(calColor.r, calColor.g, calColor.b, dragging ? 0.55 : body.containsMouse ? 0.4 : 0.28)
                                    border.width: dragging ? 1.5 : 1
                                    border.color: dragging ? block.calColor : Qt.rgba(calColor.r, calColor.g, calColor.b, 0.55)
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Rectangle {
                                        width: 3
                                        height: parent.height - 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 3
                                        radius: 2
                                        color: block.calColor
                                    }
                                    Column {
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 5; topMargin: 3 }
                                        spacing: 0
                                        Text {
                                            width: parent.width
                                            text: block.ev.title
                                            color: "white"
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                            wrapMode: block.height > 44 ? Text.WordWrap : Text.NoWrap
                                            maximumLineCount: Math.max(1, Math.floor((block.height - 20) / 14))
                                        }
                                        Text {
                                            visible: block.height > 32 || block.dragging
                                            width: parent.width
                                            text: block.dragging ? U.fmtTime(block.preview.start) + " – " + U.fmtTime(block.preview.end)
                                                : U.fmtRange(block.ev, col.modelData) + (block.ev.location ? "  ·  " + block.ev.location : "")
                                            color: Qt.rgba(1, 1, 1, block.dragging ? 0.95 : 0.65)
                                            font.pixelSize: 10
                                            font.bold: block.dragging
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // drag the body to move, the bottom edge to resize; a plain click opens it
                                    function begin(m, item) {
                                        const p = item.mapToItem(null, m.x, m.y)
                                        item.sx = p.x
                                        item.sy = p.y
                                        item.moved = false
                                    }
                                    function finish() {
                                        if (dragging) root.eventMoved(ev, preview.start, preview.end)
                                        dMin = 0; dDay = 0; dEnd = 0
                                    }

                                    MouseArea {
                                        id: body
                                        anchors.fill: parent
                                        anchors.bottomMargin: 6
                                        hoverEnabled: true
                                        preventStealing: true
                                        cursorShape: pressed && moved ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        property real sx: 0
                                        property real sy: 0
                                        property bool moved: false
                                        onPressed: m => block.begin(m, body)
                                        onPositionChanged: m => {
                                            if (!pressed || !block.writable) return
                                            const p = body.mapToItem(null, m.x, m.y)
                                            if (!moved && Math.hypot(p.x - sx, p.y - sy) < 6) return
                                            moved = true
                                            block.dMin = Math.round((p.y - sy) / root.hourHeight * 4) * 15
                                            // other days (a series asks "only this / all" when dropped)
                                            if (root.days > 1) {
                                                const di = root.dayList.findIndex(d => U.sameDay(d, col.modelData))
                                                const want = Math.round((p.x - sx) / (col.width + 4))
                                                block.dDay = Math.max(-di, Math.min(root.days - 1 - di, want))
                                            }
                                        }
                                        onReleased: block.finish()
                                        onClicked: if (!moved) root.eventClicked(block.ev, block)
                                    }
                                    MouseArea {
                                        id: grip
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        height: 7
                                        enabled: block.writable
                                        hoverEnabled: true
                                        preventStealing: true
                                        cursorShape: Qt.SizeVerCursor
                                        property real sx: 0
                                        property real sy: 0
                                        property bool moved: false
                                        onPressed: m => block.begin(m, grip)
                                        onPositionChanged: m => {
                                            if (!pressed) return
                                            const p = grip.mapToItem(null, m.x, m.y)
                                            moved = true
                                            const minLen = 15 - (block.modelData.bottom - block.modelData.top)
                                            block.dEnd = Math.max(minLen, Math.round((p.y - sy) / root.hourHeight * 4) * 15)
                                        }
                                        onReleased: block.finish()
                                    }
                                }
                            }

                            // now line
                            Rectangle {
                                visible: col.today
                                readonly property real mins: (root.now - U.dayStart(col.modelData).getTime()) / 60000
                                y: mins / 60 * root.hourHeight - 1
                                width: parent.width
                                height: 2
                                color: "#f38ba8"
                                z: 5
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    x: -4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#f38ba8"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
