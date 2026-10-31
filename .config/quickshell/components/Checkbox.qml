import QtQuick
import qs.services

// A checkbox with its label: a whole row you can click (hover tint).
// Tab / Space / Enter, focus ring and screen-reader state come from Pressable.
//
//   Checkbox { label: "Include accounts"; checked: x; onClicked: x = !x }
//
// Like ToggleSwitch it doesn't flip itself — the owner sets `checked`.
Pressable {
    id: check

    property string label
    property bool checked: false

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 16
    accessibleName: label
    accessibleRole: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        color: check.hovered ? Colors.fade(0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: Tokens.space.s8
        spacing: Tokens.space.s8
        Text {
            text: check.checked ? "󰄵" : "󰄱"
            color: check.checked ? Colors.accent : Colors.fade(0.35)
            font.pixelSize: Tokens.font.label
            font.family: Properties.fontFamily
        }
        Text {
            width: Math.max(0, check.width - 40)
            anchors.verticalCenter: parent.verticalCenter
            text: check.label
            color: check.checked ? Colors.ink : Colors.fade(0.5)
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }
}
