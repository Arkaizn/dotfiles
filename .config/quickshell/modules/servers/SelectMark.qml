import QtQuick
import qs.components
import qs.services

// The tick of the Servers window's Select mode (ServerCard, in place of the status dot).
//   SelectMark { selected: true }
Item {
    id: root
    property bool selected: false
    implicitWidth: 18; implicitHeight: 18
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.selected ? Colors.accent : "transparent"
        border.width: 1.5
        border.color: root.selected ? Colors.accent : Colors.fade(0.4)
        scale: root.selected ? 1 : 0.9
        Behavior on color { ColorAnimation { duration: Anim.fast } }
        Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.pop } }
        Text {
            anchors.centerIn: parent
            text: "󰄬"
            color: Colors.background
            opacity: root.selected ? 1 : 0
            scale: root.selected ? 1 : 0.4
            font.pixelSize: 12; font.family: Properties.fontFamily
            Behavior on opacity { NumberAnimation { duration: Anim.fast } }
            Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.pop } }
        }
    }
}
