import QtQuick
import qs.services

// On/off switch in the button style (ButtonGradient track, light knob).
// Tab / Space / Enter, focus ring and screen-reader state come from Pressable.
//
//   ToggleSwitch { checked: x; accessibleName: "Wi-Fi"; onToggled: v => x = v }
//
// It doesn't flip itself: `toggled(value)` asks, the owner sets `checked`
// (bound to the real state, so a refused change springs back).
Pressable {
    id: root

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 44
    implicitHeight: 24
    accessibleRole: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    focusRadius: height / 2
    onClicked: root.toggled(!root.checked)

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        border.width: Tokens.border.control
        border.color: Colors.line(root.checked || root.hovered ? 0.28 : 0.16)
        gradient: ButtonGradient { hovered: root.checked || root.hovered }
        Behavior on border.color { ColorAnimation { duration: Anim.fast } }

        // tint when on
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Colors.accent
            opacity: root.checked ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: Anim.normal } }
        }
    }

    Rectangle {
        width: parent.height - 8
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 4 : 4
        color: root.checked ? Colors.ink : Colors.fade(0.55)
        scale: root.pressed ? 0.85 : 1
        Behavior on x { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
        Behavior on color { ColorAnimation { duration: Anim.normal } }
        Behavior on scale { NumberAnimation { duration: Anim.fast } }
    }
}
