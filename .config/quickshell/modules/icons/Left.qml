// import Quickshell
// import Quickshell.Io
// import Quickshell.Hyprland
// import Quickshell.Services.SystemTray
// import Quickshell.DBusMenu
// import Quickshell.Widgets

import QtQuick
// import QtQuick.Controls
import QtQuick.Layouts
// import QtQuick.Shapes

import "Left"

RowLayout {
    id: left
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.leftMargin: 8
    spacing: bar.spacing

    ArchIcon {}
    Clock {}

    Row {
            Text {
                text: "Left 󰣇"
                font.pixelSize: 24
                color: "white"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Quickshell.execDetached(["swaync-client", "-t", "-sw"])
                }
            }
    }
}