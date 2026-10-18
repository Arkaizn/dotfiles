import QtQuick
import QtQuick.Layouts
import qs.services
import "CalUtil.js" as U

// One-line event: tinted pill with the calendar color, time + title.
// `filled` = solid background (all-day / multi-day events).
Rectangle {
    id: root

    required property var ev
    property var day: null
    property bool filled: ev.allDay || (day !== null && U.fullDay(ev, day))
    property bool showTime: true
    signal clicked(var ev, Item item)

    readonly property color calColor: CalendarStore.calendarMap[ev.calendar]?.color ?? Colors.color6

    implicitHeight: 20
    radius: 5
    color: filled ? Qt.rgba(calColor.r, calColor.g, calColor.b, hover.hovered ? 0.95 : 0.8)
                  : Qt.rgba(calColor.r, calColor.g, calColor.b, hover.hovered ? 0.32 : 0.2)
    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 5

        Rectangle {
            visible: !root.filled
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: root.calColor
        }
        Text {
            visible: root.showTime && !root.filled
            text: U.fmtTime(root.ev.start)
            color: Colors.fade(0.6)
            font.pixelSize: 10
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            text: root.ev.title
            color: root.filled ? U.onColor(root.calColor) : Colors.ink
            font.pixelSize: 11
            font.bold: root.filled
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }

    // MouseArea (not TapHandler) so the click doesn't also reach the day cell below
    MouseArea {
        id: hover
        readonly property bool hovered: containsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked(root.ev, root)
    }
}
