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
    signal groupMoved(int dMin, int dDay)                  // a selected event dragged: all selected ones move

    // the selected events follow the one being dragged (preview only)
    property string groupDrag: ""
    property int groupMin: 0
    property int groupDay: 0

    // y (px in a day column) → minutes since midnight, on 15 min steps (1 with Shift held)
    function snapMin(y, step) { const st = step || 15; return Math.max(0, Math.min(24 * 60, Math.round(y / hourHeight * 60 / st) * st)) }
    // a drag of dy px → minutes, on 15 min steps or, with Shift held, minute by minute
    function stepOf(mods) { return (mods & Qt.ShiftModifier) ? 1 : 15 }
    function dragMin(dy, mods) { const st = stepOf(mods); return Math.round(dy / hourHeight * 60 / st) * st }
    // the room (minutes) a very short event's one-line label needs
    readonly property real labelSpan: 18 / hourHeight * 60
    // day + minutes → ms (via setHours, so daylight saving days work)
    function at(day, mins) { const d = new Date(day); d.setHours(0, mins, 0, 0); return d.getTime() }
    // ev moved by minutes / days and stretched at the end
    function shifted(ev, dMin, dDay, dEnd) {
        const s = new Date(ev.start); s.setDate(s.getDate() + dDay); s.setMinutes(s.getMinutes() + dMin)
        const e = new Date(ev.end); e.setDate(e.getDate() + dDay); e.setMinutes(e.getMinutes() + dMin + dEnd)
        return Object.assign({}, ev, { start: s.getTime(), end: e.getTime() })
    }

    readonly property int gutter: 52
    // zoom: Ctrl + wheel, Ctrl +/-/0, the toolbar buttons (CalendarStore.zoom, %)
    readonly property real hourHeight: Math.round(52 * CalendarStore.zoom / 100)
    // labels / lines every 30 or 15 min once there's room for them
    readonly property int labelStep: hourHeight >= 180 ? 15 : hourHeight >= 90 ? 30 : 60

    // zoom keeping the time at y (px in the visible grid, default its middle) in place
    function zoom(dir, y) {
        const at = y ?? flick.height / 2
        const hour = (flick.contentY + at - 8) / root.hourHeight
        if (dir === 0) CalendarStore.zoomReset()
        else CalendarStore.zoomBy(dir)
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, hour * root.hourHeight + 8 - at))
    }
    readonly property var dayList: {
        const out = []
        for (let i = 0; i < days; i++) out.push(U.addDays(start, i))
        return out
    }

    // the now-line moves on the minute (Time ticks with the system clock)
    readonly property double now: { Time.minutes; return Date.now() }

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
                        color: head.today ? Colors.color6 : U.weekday(head.modelData) >= 5 ? Colors.fade(0.32) : Colors.fade(0.5)
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    Rectangle {
                        implicitWidth: Math.max(30, dnum.implicitWidth + 14)
                        implicitHeight: 30
                        radius: 15
                        color: head.today ? Colors.color6 : dayHover.hovered ? Colors.fade(0.1) : "transparent"
                        Text {
                            id: dnum
                            anchors.centerIn: parent
                            text: head.modelData.getDate()
                            color: head.today ? U.onColor(Colors.color6) : U.weekday(head.modelData) >= 5 ? Colors.fade(0.6) : Colors.ink
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
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        Text {
            width: root.gutter - 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: "all-day"
            color: Colors.fade(0.35)
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
                            color: Colors.fade(0.5)
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
        color: Colors.card
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
            SmoothWheel { flick: flick; step: Math.min(root.hourHeight, 120); acceptedModifiers: Qt.NoModifier }
            WheelHandler {
                acceptedModifiers: Qt.ControlModifier
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real acc: 0
                onWheel: event => {
                    acc += event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y * 4
                    if (Math.abs(acc) < 120) return
                    const dir = acc > 0 ? 1 : -1
                    acc = 0
                    root.zoom(dir, point.position.y)
                }
            }

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
                            color: Colors.fade(0.35)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                        }
                        Rectangle {
                            x: root.gutter
                            width: parent.width - root.gutter - 8
                            height: 1
                            color: Colors.fade(parent.index > 0 ? 0.06 : 0)
                        }
                        // half hour (quarters when zoomed in), labelled once there's room
                        Repeater {
                            model: root.labelStep === 15 ? [15, 30, 45] : [30]
                            Item {
                                id: tick
                                required property int modelData
                                y: tick.modelData / 60 * root.hourHeight
                                width: parent.width
                                Text {
                                    visible: tick.modelData % root.labelStep === 0
                                    width: root.gutter - 10
                                    y: -height / 2
                                    horizontalAlignment: Text.AlignRight
                                    text: U.pad(tick.parent.index) + ":" + tick.modelData
                                    color: Colors.fade(0.22)
                                    font.pixelSize: 9
                                    font.family: Properties.fontFamily
                                }
                                Rectangle {
                                    x: root.gutter
                                    width: parent.width - root.gutter - 8
                                    height: 1
                                    color: Colors.fade(tick.modelData === 30 ? 0.035 : 0.02)
                                }
                            }
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
                                CalendarStore.eventsOn(modelData).filter(e => !U.fullDay(e, modelData)), modelData, root.labelSpan)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1

                            // line between the days (in the middle of the 4 px gap)
                            Rectangle {
                                visible: root.days > 1 && col.index > 0
                                x: -2.5
                                width: 1
                                height: parent.height
                                color: Colors.fade(0.09)
                            }

                            // weekend: a shade darker
                            Rectangle {
                                anchors.fill: parent
                                visible: root.days > 1 && U.weekday(col.modelData) >= 5
                                color: Colors.shade(0.13)
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
                                property int step: 15
                                readonly property int fromMin: Math.min(root.snapMin(pressY, step), root.snapMin(curY, step))
                                readonly property int toMin: Math.max(Math.max(root.snapMin(pressY, step), root.snapMin(curY, step)), fromMin + step)

                                onPressed: m => { pressY = m.y; curY = m.y; dragging = false; step = root.stepOf(m.modifiers) }
                                onPositionChanged: m => {
                                    if (!pressed) return
                                    step = root.stepOf(m.modifiers)
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
                                    color: Colors.ink
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
                                    property int ownMin: 0
                                    property int ownDay: 0
                                    property int dEnd: 0
                                    readonly property bool picked: CalendarStore.isSelected(ev.id)
                                    // another selected event is being dragged: this one moves along
                                    readonly property bool follows: picked && root.groupDrag !== "" && root.groupDrag !== ev.id
                                    readonly property int dMin: follows ? root.groupMin : ownMin
                                    readonly property int dDay: follows ? root.groupDay : ownDay
                                    readonly property bool dragging: dMin !== 0 || dDay !== 0 || dEnd !== 0
                                    readonly property var preview: dragging
                                        ? root.shifted(ev, dMin, dDay, dEnd) : ev

                                    // exactly as long as the event (a 4 min one is 4 min tall); one
                                    // too short for its text gets a one-line label across it instead
                                    readonly property real span: (modelData.bottom - modelData.top + dEnd) / 60 * root.hourHeight
                                    readonly property bool compact: span < 30
                                    x: modelData.col * colW + 1 + dDay * (col.width + 4)
                                    y: (modelData.top + dMin) / 60 * root.hourHeight
                                    width: dragging ? col.width - 2 : colW - 2
                                    height: Math.max(3, span > 8 ? span - 1 : span)
                                    z: dragging ? 10 : body.containsMouse ? 3 : compact ? 2 : 1
                                    radius: Math.min(7, height / 2)
                                    clip: !compact
                                    color: Qt.rgba(calColor.r, calColor.g, calColor.b, dragging ? 0.55 : body.containsMouse ? 0.4 : 0.28)
                                    border.width: picked ? 2 : dragging ? 1.5 : 1
                                    border.color: picked ? Colors.color6 : dragging ? block.calColor : Qt.rgba(calColor.r, calColor.g, calColor.b, 0.55)
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Rectangle {
                                        width: 3
                                        height: block.compact ? parent.height : parent.height - 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: block.compact ? 0 : 3
                                        radius: 2
                                        color: block.calColor
                                    }
                                    // selected (Ctrl / Shift + click)
                                    Rectangle {
                                        visible: block.picked
                                        anchors.right: parent.right
                                        anchors.rightMargin: 4
                                        anchors.top: block.compact ? undefined : parent.top
                                        anchors.topMargin: 4
                                        anchors.verticalCenter: block.compact ? parent.verticalCenter : undefined
                                        width: 14; height: 14; radius: 7
                                        z: 2
                                        color: Colors.color6
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰄬"
                                            color: U.onColor(Colors.color6)
                                            font.pixelSize: 10
                                            font.family: Properties.fontFamily
                                        }
                                    }
                                    // short event: title + time on one line, centered on it
                                    Rectangle {
                                        visible: block.compact
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 6
                                        width: Math.min(parent.width - 8, compactText.implicitWidth + 10)
                                        height: 15
                                        radius: 5
                                        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.85)
                                        border.width: 1
                                        border.color: Qt.rgba(block.calColor.r, block.calColor.g, block.calColor.b, 0.7)
                                        Text {
                                            id: compactText
                                            anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: block.ev.title + "  " + (block.dragging ? U.fmtTime(block.preview.start) + " – " + U.fmtTime(block.preview.end)
                                                                                           : U.fmtTime(block.ev.start))
                                            color: Colors.ink
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Column {
                                        visible: !block.compact
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 5; topMargin: 3 }
                                        spacing: 0
                                        Text {
                                            width: parent.width
                                            text: block.ev.title
                                            color: Colors.ink
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
                                            color: Colors.fade(block.dragging ? 0.95 : 0.65)
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
                                    // the drag state is reset before the move is sent: the move rebuilds
                                    // the blocks, and a new one must not still follow the old offset
                                    function finish() {
                                        const group = root.groupDrag === ev.id
                                        const m = ownMin, d = ownDay, e = ev, p = preview, was = dragging
                                        ownMin = 0; ownDay = 0; dEnd = 0
                                        root.groupDrag = ""; root.groupMin = 0; root.groupDay = 0
                                        if (group && (m !== 0 || d !== 0)) root.groupMoved(m, d)
                                        else if (!group && was) root.eventMoved(e, p.start, p.end)
                                    }

                                    MouseArea {
                                        id: body
                                        // a tiny event can still be hit: at least as tall as its label
                                        anchors.fill: parent
                                        anchors.topMargin: block.compact ? Math.min(0, (block.height - 16) / 2) : 0
                                        anchors.bottomMargin: block.compact ? Math.min(0, (block.height - 16) / 2) : 6
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
                                            block.ownMin = root.dragMin(p.y - sy, m.modifiers)
                                            // other days (a series asks "only this / all" when dropped)
                                            if (root.days > 1) {
                                                const di = root.dayList.findIndex(d => U.sameDay(d, col.modelData))
                                                const want = Math.round((p.x - sx) / (col.width + 4))
                                                block.ownDay = Math.max(-di, Math.min(root.days - 1 - di, want))
                                            }
                                            if (block.picked && CalendarStore.selectedCount > 1) {
                                                root.groupDrag = block.ev.id
                                                root.groupMin = block.ownMin
                                                root.groupDay = block.ownDay
                                            }
                                        }
                                        onReleased: block.finish()
                                        // Ctrl / Shift + click: select it (several events at once)
                                        onClicked: m => {
                                            if (moved) return
                                            if (m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) CalendarStore.toggleSelect(block.ev)
                                            else root.eventClicked(block.ev, block)
                                        }
                                    }
                                    MouseArea {
                                        id: grip
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                                  bottomMargin: block.compact ? Math.min(0, (block.height - 16) / 2) - 3 : 0 }
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
                                            const minLen = root.stepOf(m.modifiers) - (block.modelData.bottom - block.modelData.top)
                                            block.dEnd = Math.max(minLen, root.dragMin(p.y - sy, m.modifiers))
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
                                color: Colors.red
                                z: 5
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    x: -4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Colors.red
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
