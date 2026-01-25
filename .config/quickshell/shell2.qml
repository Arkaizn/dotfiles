//@ pragma UseQApplication

import Quickshell
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

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
        }
}