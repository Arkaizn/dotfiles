import QtQuick
import QtQuick.Layouts
import qs.services

// A chip you switch on and off: quick filters (unread, starred), a choice
// among several (monitors). Tab / Space / Enter, focus ring and tooltip come
// from Pressable.
//
//   FilterChip { icon: "󰇮"; text: "Unread"; checked: f; onToggled: f = !f }
//   FilterChip { text: "eDP-1  (not connected)"; dim: true; checked: on; onClicked: … }
//
// It doesn't flip itself — the owner sets `checked`. `toggled` and `clicked`
// both fire on a click (two names for the two ways it's used).
Pressable {
    id: root
    property string icon: ""
    property string text: ""
    property bool checked: false
    property bool dim: false            // greyed label (e.g. a monitor that isn't connected)
    signal toggled()

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 26
    accessibleName: text !== "" ? text : tooltip
    accessibleRole: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    focusRadius: height / 2
    onClicked: root.toggled()

    scale: pressed ? Properties.onPressedButtonScale : 1
    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Colors.alpha(Colors.accent, 0.18)
             : root.hovered ? Colors.fade(0.07) : Colors.fade(0.035)
        border.width: Tokens.border.thin
        border.color: root.checked ? Colors.alpha(Colors.accent, 0.5) : Colors.fade(0.08)
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.checked ? Colors.accent : Colors.fade(0.6)
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.checked ? Colors.ink : root.dim ? Colors.textFaint : Colors.fade(0.65)
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
        }
    }
}
