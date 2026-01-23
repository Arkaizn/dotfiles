import Quickshell
// import Quickshell.Io
// import Quickshell.Hyprland
// import Quickshell.Services.SystemTray
// import Quickshell.DBusMenu
// import Quickshell.Widgets

import QtQuick
// import QtQuick.Controls
import QtQuick.Layouts
// import QtQuick.Shapes

import "../.."

RowLayout {
    id: left
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.margins: 0
    spacing: 10

    // 
    Row {
        Text {
            text: "Left 󰣇"
            font.pixelSize: 24
            color: "white"
            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.Io.exec("swaync")
            }
        }
    }

    Rectangle {
    width: 30; height: 30
    color: "green"

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse)=> {
            if (mouse.button == Qt.RightButton)
                parent.color = 'blue';
            else
                parent.color = 'red';
        }
    }
}

}