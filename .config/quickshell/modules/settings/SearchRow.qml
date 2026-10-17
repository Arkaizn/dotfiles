import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../keybinds"
import "SettingsSearch.js" as SI

// One search result that leads somewhere (a page, a place on a page, a
// keybind, a network profile, …): icon, highlighted name, where it is,
// keys for keybinds, and an arrow. Click (or Enter on it) to go there.
Rectangle {
    id: row
    required property var entry
    required property string query
    property bool selected: false
    signal activated()

    implicitHeight: Math.max(52, rowLayout.implicitHeight + 18)
    radius: 10
    color: selected ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.12)
         : hover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
    border.width: selected ? 1 : 0
    border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45)
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.activated() }

    RowLayout {
        id: rowLayout
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 12

        Rectangle {
            width: 30; height: 30; radius: 8
            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, row.selected ? 0.2 : 0.1)
            Text {
                anchors.centerIn: parent
                text: row.entry.icon ?? "󰍉"
                color: Colors.color6
                font.pixelSize: 15
                font.family: Properties.fontFamily
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: SI.highlight(row.entry.label ?? "", row.query, Colors.color6.toString())
                textFormat: Text.StyledText
                color: "white"
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: [row.entry.crumb, row.entry.desc].filter(x => x).join("  ·  ")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }

        // keybinds: their keys
        RowLayout {
            visible: (row.entry.keys ?? []).length > 0
            spacing: 3
            Repeater {
                model: row.entry.keys ?? []
                Keycap { required property string modelData; key: modelData; compact: true }
            }
        }

        Text {
            text: row.entry.kind === "action" ? "󰐊" : "󰅂"
            color: Qt.rgba(1, 1, 1, row.selected || hover.hovered ? 0.8 : 0.3)
            font.pixelSize: 14
            font.family: Properties.fontFamily
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
}
