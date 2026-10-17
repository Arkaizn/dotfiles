import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Events of the day picked in DashboardCalendar (today by default), from the
// calendar app (CalendarStore). Click one to open the calendar on that day.
Item {
    id: root

    property date day: new Date()
    clip: true

    readonly property bool isToday: sameDay(day, new Date())

    // another day picked: the list slides in from that side
    property date lastDay: day
    onDayChanged: {
        const dir = day > lastDay ? 1 : day < lastDay ? -1 : 0
        lastDay = day
        if (dir === 0) return
        daySlide.stop()
        daySlideX.from = dir * 24
        daySlide.start()
    }
    ParallelAnimation {
        id: daySlide
        NumberAnimation { id: daySlideX; target: listShift; property: "x"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "opacity"; from: 0.2; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    readonly property var events: CalendarStore.eventsOn(day).slice().sort((a, b) =>
        (b.allDay - a.allDay) || a.start - b.start)
    // with nothing left today: the next thing coming up
    readonly property var nextUp: {
        if (!isToday) return null
        const now = Date.now()
        if (events.some(e => e.end > now)) return null
        return CalendarStore.visibleEvents.find(e => e.start > now) ?? null
    }

    // minute ticker so past events dim on time
    property double now: Date.now()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function pad(n) { return String(n).padStart(2, "0") }
    function hm(t) { const d = new Date(t); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
    function iso(d) { d = new Date(d); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    // close the dashboard, then: openDate / newEvent <day> or showEvent <id>
    function call(fn, arg) {
        Quickshell.execDetached(["sh", "-c", 'qs ipc call dashboard close; qs ipc call calendar "$1" "$2"', "sh", fn, arg])
    }
    function openCalendar(d) { call("openDate", iso(d)) }
    function timeText(e) {
        if (e.allDay) return "all day"
        const ds = new Date(day); ds.setHours(0, 0, 0, 0)
        if (e.start < ds.getTime()) return "→ " + hm(e.end)
        return hm(e.start)
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        transform: Translate { id: listShift }

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.isToday ? "Today"
                        : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][root.day.getDay()]
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.day.getDate() + ". " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
                          "Aug", "Sep", "Oct", "Nov", "Dec"][root.day.getMonth()]
                          + (root.events.length ? "  ·  " + root.events.length + (root.events.length === 1 ? " event" : " events") : "")
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            IconButton {
                implicitWidth: 26; implicitHeight: 26
                iconSize: 12
                icon: "󰐕"
                tooltip: "New event on this day"
                onClicked: root.call("newEvent", root.iso(root.day))
            }
            IconButton {
                implicitWidth: 26; implicitHeight: 26
                iconSize: 12
                icon: "󰃭"
                tooltip: "Open calendar"
                onClicked: root.openCalendar(root.day)
            }
        }

        // events
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

        ListView {
            anchors.fill: parent
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.events
            // rows grow a little on hover: keep them off the clipping edges
            leftMargin: 4
            rightMargin: 4
            topMargin: 2
            bottomMargin: 2

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property color calColor: CalendarStore.calendarMap[modelData.calendar]?.color ?? Colors.color6
                readonly property bool past: !modelData.allDay && modelData.end < root.now
                readonly property bool live: !modelData.allDay && modelData.start <= root.now && modelData.end > root.now
                width: ListView.view.width - 8
                height: 40
                radius: 9
                color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07)
                     : live ? Qt.rgba(calColor.r, calColor.g, calColor.b, 0.14) : Qt.rgba(1, 1, 1, 0.03)
                opacity: past ? 0.45 : 1
                scale: mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? 1.02 : 1
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 24
                        radius: 2
                        color: row.calColor
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.timeText(row.modelData) + (row.modelData.location ? "  ·  " + row.modelData.location : "")
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: row.live
                        text: "now"
                        color: row.calColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                }
                // left: open this event · right: new event on this day
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => m.button === Qt.RightButton ? root.call("newEvent", root.iso(root.day))
                                                                : root.call("showEvent", row.modelData.id)
                }
            }

        }

            // empty state
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                visible: root.events.length === 0
                spacing: 4
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰃮"
                    color: Qt.rgba(1, 1, 1, 0.25)
                    font.pixelSize: 26
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Nothing planned"
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                }
            }
        }

        // next event when today is done
        Rectangle {
            Layout.fillWidth: true
            visible: root.nextUp !== null
            implicitHeight: 40
            radius: 9
            color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.03)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Text {
                    text: "Next"
                    color: Colors.color6
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        const e = root.nextUp
                        if (!e) return ""
                        const d = new Date(e.start)
                        const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1)
                        const soon = d.getTime() - Date.now() < 6 * 86400000
                        const when = root.sameDay(d, tomorrow) ? "Tomorrow"
                                   : soon ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()]
                                   : d.getDate() + "." + (d.getMonth() + 1) + "."
                        return e.title + "  ·  " + when + (e.allDay ? "" : " " + root.hm(e.start))
                    }
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.call("showEvent", root.nextUp.id)
            }
        }
    }
}
