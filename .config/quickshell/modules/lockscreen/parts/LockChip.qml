import QtQuick
import qs.services

// Small panel-styled label at the top of the lockscreen / login screen
// (battery, Bluetooth device). `warn` turns the text red (low battery).
Rectangle {
    id: root

    property string text: ""
    property bool warn: false

    implicitWidth: label.implicitWidth + 20
    implicitHeight: 30
    radius: Properties.radius              // like the buttons, not a full pill
    color: Properties.panelColor
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.warn ? Colors.red : Colors.ink
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
}
