import QtQuick
import qs.services

// The keyboard focus ring: an accent outline just outside the control.
// Pressable has one; other focusable things (rows, cards, custom inputs) add
//   FocusRing { controlRadius: Tokens.radius.lg; shown: row.activeFocus }   // as a child of the row
Rectangle {
    id: ring

    property bool shown: false
    property real gap: 2          // between the control and the ring
    property real controlRadius: Tokens.radius.md   // the control's own corner radius

    anchors.fill: parent
    anchors.margins: -(gap + Tokens.border.focus)
    radius: controlRadius + gap + Tokens.border.focus   // concentric with the control
    color: "transparent"
    border.width: Tokens.border.focus
    border.color: Colors.focus
    z: 100
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
}
