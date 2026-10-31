import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Big button of the capture menu: icon, label and its number key.
// A tile, not a regular button (the menu is a grid of them); keyboard, focus
// ring and screen-reader name from Pressable, the number keys from CaptureMenu.
Pressable {
    id: btn
    property string icon
    property string text
    property string key: ""
    property bool danger: false

    readonly property color tint: danger ? Colors.danger : Colors.accent

    Layout.fillWidth: true
    implicitHeight: 74
    accessibleName: text + (key !== "" ? " (" + key + ")" : "")
    focusRadius: Tokens.radius.xl
    scale: pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Anim.instant } }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: btn.hovered ? Colors.alpha(btn.tint, 0.18) : Colors.fade(0.05)
        border.width: Tokens.border.thin
        border.color: btn.hovered ? Colors.alpha(btn.tint, 0.6) : Colors.fade(0.08)
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Tokens.space.s4
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: btn.icon
            color: btn.tint
            font.pixelSize: Tokens.icon.xl
            font.family: Properties.fontFamily
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: btn.text
            color: Colors.ink
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }
    }
    Text {
        visible: btn.key !== ""
        anchors { top: parent.top; right: parent.right; margins: 7 }
        text: btn.key
        color: Colors.fade(0.35)
        font.pixelSize: Tokens.font.micro
        font.family: Properties.fontFamily
    }
}
