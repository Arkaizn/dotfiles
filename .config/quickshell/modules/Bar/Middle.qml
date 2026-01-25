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

import "Middle"

RowLayout {
    id: middle
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    spacing: bar.spacing

    GPUusage {}
    CPUusage {}
    Memusage {}
    Workspaces {}
    GPUtemp {}
    CPUtemp {}
}