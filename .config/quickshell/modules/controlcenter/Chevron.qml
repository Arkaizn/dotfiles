import QtQuick
import qs.services

// Rotating ⌄ for dropdown headers
Text {
    property bool open: false
    text: "󰅀"
    color: Qt.rgba(1, 1, 1, 0.6)
    font.pixelSize: 13
    font.family: Properties.fontFamily
    rotation: open ? 180 : 0
    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
}
