import QtQuick
import QtQuick.Layouts
import qs.services

// Toggle chip of the quick filter bar (unread, starred, attachments).
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool checked: false
    property string tooltip: ""
    signal toggled()

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 26
    radius: 13
    color: checked ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18)
         : mouse.containsMouse ? Colors.fade(0.07) : Colors.fade(0.035)
    border.width: 1
    border.color: checked ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.5) : "transparent"
    scale: mouse.pressed ? Properties.onPressedButtonScale : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.checked ? Colors.color6 : Colors.fade(0.6)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.checked ? Colors.ink : Colors.fade(0.65)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
