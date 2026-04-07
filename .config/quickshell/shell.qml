//@ pragma UseQApplication

import Quickshell
import QtQuick
// import Quickshell.Io
// import Quickshell.Hyprland
// import Quickshell.Services.SystemTray
// import Quickshell.DBusMenu
// import Quickshell.Widgets

// import QtQuick
// import QtQuick.Controls
// import QtQuick.Layouts
// import QtQuick.Shapes

import "."
import "modules"
import "services" as QsServices

ShellRoot {
    id: root
    Variants {
        model: Quickshell.screens
        Bar {}
    }
    
}