import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

RowLayout {
    id: fr
    property string name
    property string value
    Layout.fillWidth: true
    spacing: Tokens.space.s8
    Text { text: "󰈐"; color: Colors.fade(0.4); font.pixelSize: Tokens.font.body; font.family: Properties.fontFamily }
    Text { Layout.fillWidth: true; text: fr.name; color: Colors.fade(0.7); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight }
    Text { text: fr.value; color: Colors.ink; font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily }
}
