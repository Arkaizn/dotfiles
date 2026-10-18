import QtQuick
import qs.services

// A key: little raised cap, modifiers tinted with the accent color.
//   Keycap { key: "Mod" }      (labels come from Keybinds.keyLabel)
Item {
    id: cap
    property string key
    property bool compact: false
    readonly property bool modifier: Keybinds.isModifier(key)
    implicitWidth: Math.max(compact ? 20 : 24, label.implicitWidth + (compact ? 10 : 14))
    implicitHeight: compact ? 20 : 24

    // the "side" of the key, peeking out below the top
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.35)
    }
    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: 2
        radius: 6
        color: cap.modifier ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16) : Colors.fade(0.08)
        border.width: 1
        border.color: cap.modifier ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45) : Colors.fade(0.16)

        Text {
            id: label
            anchors.centerIn: parent
            text: Keybinds.keyLabel(cap.key)
            color: cap.modifier ? Colors.color6 : Colors.ink
            font.pixelSize: cap.compact ? 10 : 11
            font.bold: true
            font.family: Properties.fontFamily
        }
    }
}
