import QtQuick
import qs.services

// A small fake panel in a scheme's colors (background, accent, text, colors 1–5).
Rectangle {
    id: root
    property var scheme: null
    implicitWidth: 220
    implicitHeight: 74
    radius: Tokens.radius.lg
    color: scheme?.special?.background ?? "#000"
    border.width: 1
    border.color: Colors.line(0.12)
    Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.space.s12 }
        spacing: Tokens.space.s4
        Text { text: "Accent text"; color: root.scheme?.colors?.color6 ?? "#fff"; font.bold: true; font.pixelSize: Tokens.font.body; font.family: Properties.fontFamily }
        Text { text: "Normal text"; color: root.scheme?.special?.foreground ?? "#fff"; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
        Row {
            spacing: Tokens.space.s4
            Repeater {
                model: [1, 2, 3, 4, 5]
                Rectangle { required property int modelData; width: 26; height: 8; radius: Tokens.radius.sm; color: root.scheme?.colors?.["color" + modelData] ?? "#888" }
            }
        }
    }
}
