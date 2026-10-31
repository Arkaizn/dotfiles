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
    radius: Tokens.radius.xl
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.space.s10
        anchors.leftMargin: Tokens.space.s12
        spacing: Tokens.space.s1
        RowLayout {
            spacing: Tokens.space.s6
            Text {
                text: card.icon
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }
            Text {
                text: card.label.toUpperCase()
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.micro
                font.bold: true
                font.letterSpacing: 1
                font.family: Properties.fontFamily
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            Rectangle {
                visible: card.dot.a > 0
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: Tokens.radius.sm
                color: card.dot
            }
            Text {
                Layout.fillWidth: true
                text: card.value
                color: Colors.ink
                font.pixelSize: Tokens.font.body
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: card.sub
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.micro
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }
}
