import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// Events of the day picked in DashboardCalendar (today by default), from the
// calendar app (CalendarStore). Click one to open the calendar on that day.
Item {
    id: root

    property date day: new Date()
    clip: true

    readonly property bool isToday: sameDay(day, new Date(now))

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
        NumberAnimation { id: daySlideX; target: listShift; property: "x"; to: 0; duration: Anim.medium; easing.type: Anim.standard }
        NumberAnimation { target: content; property: "opacity"; from: 0.2; to: 1; duration: Anim.medium; easing.type: Anim.standard }
    }
    readonly property var events: CalendarStore.eventsOn(day).slice().sort((a, b) =>
        (b.allDay - a.allDay) || a.start - b.start)
    // with nothing left today: the next thing coming up
    readonly property var nextUp: {
        if (!isToday) return null
        const now = root.now
        if (events.some(e => e.end > now)) return null
        return CalendarStore.visibleEvents.find(e => e.start > now) ?? null
    }

    // on the minute (Time ticks with the system clock), so "now" / past show on time
    readonly property double now: { Time.minutes; return Date.now() }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function hm(t) { return Format.hm(t) }
    function iso(d) { return Format.day(d) }
    // close the dashboard, then: openDate / newEvent <day> or showEvent <id>
    function call(fn, arg) {
        Panels.close("dashboard")
        Panels.call("calendar", fn, arg)
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
        anchors.margins: Tokens.space.s12
        spacing: Tokens.space.s8
        transform: Translate { id: listShift }

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
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
                    color: Colors.ink
                    font.pixelSize: Tokens.font.label
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
                    color: Colors.fade(0.45)
                    font.pixelSize: Tokens.font.caption
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
            spacing: Tokens.space.s4
            boundsBehavior: Flickable.StopAtBounds
            model: root.events
            // rows grow a little on hover: keep them off the clipping edges
            leftMargin: Tokens.space.s4
            rightMargin: Tokens.space.s4
            topMargin: Tokens.space.s2
            bottomMargin: Tokens.space.s2

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property color calColor: CalendarStore.calendarMap[modelData.calendar]?.color ?? Colors.color6
                readonly property bool past: !modelData.allDay && modelData.end < root.now
                readonly property bool live: !modelData.allDay && modelData.start <= root.now && modelData.end > root.now
                width: ListView.view.width - 8
                height: 40
                radius: 9
                color: mouse.containsMouse ? Colors.fade(0.07)
                     : live ? Qt.rgba(calColor.r, calColor.g, calColor.b, 0.14) : Colors.fade(0.03)
                opacity: past ? 0.45 : 1
                scale: mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? 1.02 : 1
                Behavior on color { ColorAnimation { duration: Anim.fast } }
                Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space.s8
                    anchors.rightMargin: Tokens.space.s8
                    spacing: Tokens.space.s8
                    Rectangle {
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 24
                        radius: Tokens.radius.xs
                        color: row.calColor
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            color: Colors.ink
                            font.pixelSize: Tokens.font.small
                            font.bold: true
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.timeText(row.modelData) + (row.modelData.location ? "  ·  " + row.modelData.location : "")
                            color: Colors.fade(0.5)
                            font.pixelSize: Tokens.font.micro
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: row.live
                        text: "now"
                        color: row.calColor
                        font.pixelSize: Tokens.font.micro
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
            EmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: root.events.length === 0
                compact: true
                icon: "󰃮"
                text: "Nothing planned"
            }
        }

        // next event when today is done
        Rectangle {
            Layout.fillWidth: true
            visible: root.nextUp !== null
            implicitHeight: 40
            radius: 9
            color: nextMouse.containsMouse ? Colors.fade(0.07) : Colors.fade(0.03)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space.s10
                anchors.rightMargin: Tokens.space.s10
                spacing: Tokens.space.s8
                Text {
                    text: "Next"
                    color: Colors.color6
                    font.pixelSize: Tokens.font.micro
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
                    color: Colors.fade(0.75)
                    font.pixelSize: Tokens.font.caption
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
