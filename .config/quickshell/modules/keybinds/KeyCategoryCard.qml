import QtQuick
import QtQuick.Layouts
import qs.services

// One category of keybinds: icon + name + count, then its rows.
//   category: { name, icon, rows: [Keybinds.binds rows] }
Rectangle {
    id: card
    property var category
    property bool compact: false
    property bool editable: false
    signal editRequested(var item)
    implicitHeight: cardCol.implicitHeight + 20
    radius: 12
    color: Colors.shade(0.27)
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder

    ColumnLayout {
        id: cardCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 2

        RowLayout {
            Layout.leftMargin: 6
            Layout.bottomMargin: 4
            spacing: 8
            Text {
                text: card.category.icon
                color: Colors.color6
                font.pixelSize: card.compact ? 14 : 15
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: card.category.name
                color: Colors.ink
                font.pixelSize: card.compact ? 12 : 13
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                text: card.category.rows.length
                color: Colors.fade(0.35)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }

        Repeater {
            model: card.category.rows
            BindRow {
                required property var modelData
                Layout.fillWidth: true
                bind: modelData
                compact: card.compact
                editable: card.editable
                onEditRequested: item => card.editRequested(item)
            }
        }
    }
}
