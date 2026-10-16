import QtQuick
import QtQuick.Layouts
import qs.services

// Small labelled card in the event details: icon + LABEL, value, sub line.
Rectangle {
    id: card
    property string icon: ""
    property string label: ""
    property string value: ""
    property string sub: ""
    property color dot: "transparent"
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: 64
    radius: 12
    color: "#27000000"
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: 12
        spacing: 1
        RowLayout {
            spacing: 6
            Text {
                text: card.icon
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
            Text {
                text: card.label.toUpperCase()
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1
                font.family: Properties.fontFamily
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                visible: card.dot.a > 0
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: card.dot
            }
            Text {
                Layout.fillWidth: true
                text: card.value
                color: "white"
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: card.sub
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 10
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }
}
