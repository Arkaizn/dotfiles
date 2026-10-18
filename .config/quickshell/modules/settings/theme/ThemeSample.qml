import QtQuick
import qs.services

// A small fake panel in a scheme's colors (background, accent, text, colors 1–5).
Rectangle {
    id: root
    property var scheme: null
    implicitWidth: 220
    implicitHeight: 74
    radius: 10
    color: scheme?.special?.background ?? "#000"
    border.width: 1
    border.color: Colors.fade(0.12)
    Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
        spacing: 4
        Text { text: "Accent text"; color: root.scheme?.colors?.color6 ?? "#fff"; font.bold: true; font.pixelSize: 13; font.family: Properties.fontFamily }
        Text { text: "Normal text"; color: root.scheme?.special?.foreground ?? "#fff"; font.pixelSize: 12; font.family: Properties.fontFamily }
        Row {
            spacing: 4
            Repeater {
                model: [1, 2, 3, 4, 5]
                Rectangle { required property int modelData; width: 26; height: 8; radius: 4; color: root.scheme?.colors?.["color" + modelData] ?? "#888" }
            }
        }
    }
}
