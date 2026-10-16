import QtQuick
import qs.components
import qs.services

// On/off switch in the button style (ButtonGradient track, light knob).
//   ToggleSwitch { checked: x; onToggled: v => x = v }
Item {
    id: root

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 44
    implicitHeight: 24

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, root.checked || mouse.containsMouse ? 0.28 : 0.16)
        gradient: ButtonGradient { hovered: root.checked || mouse.containsMouse }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        // tint when on
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Colors.color6
            opacity: root.checked ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    Rectangle {
        width: parent.height - 8
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 4 : 4
        color: root.checked ? "white" : Qt.rgba(1, 1, 1, 0.55)
        scale: mouse.pressed ? 0.85 : 1
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
