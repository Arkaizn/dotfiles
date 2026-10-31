import QtQuick
import qs.services

// Rotating ⌄ for dropdown headers and collapsible sections
//   Chevron { open: list.visible }
Text {
    property bool open: false
    text: "󰅀"
    color: Colors.fade(0.6)
    font.pixelSize: Tokens.font.body
    font.family: Properties.fontFamily
    rotation: open ? 180 : 0
    Behavior on rotation { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
}
