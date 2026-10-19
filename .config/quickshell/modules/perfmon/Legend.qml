import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

RowLayout {
    id: lg
    property color color
    property string text
    spacing: 5
    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 2; color: lg.color }
    Text { text: lg.text; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
}
