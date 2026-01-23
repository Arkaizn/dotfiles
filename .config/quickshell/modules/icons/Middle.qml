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
    id: middle
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: 16
    spacing: 8

    Row {
        Text {
            text: "Middle 󰣇"
            font.pixelSize: 24
            color: "white"
            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.Io.exec("swaync")
            }
        }
    }
}