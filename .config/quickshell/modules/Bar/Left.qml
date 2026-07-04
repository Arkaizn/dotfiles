import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

import "Left"
import "Left/Tray"

RowLayout {
    id: left
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.leftMargin: Properties.barMarginLeft + 8
    spacing: Properties.spacing

     
    ArchIcon {}

    // Workspace_niri for Niri
    // Workspace_Hyprland for Hyprland
    Loader {
        sourceComponent: Quickshell.env("NIRI_SOCKET") !== null // check if socket is Niri else use hyprland
            ? niriWorkspacesComponent
            : hyprlandWorkspacesComponent
    }
    Component {
        id: niriWorkspacesComponent
        Workspaces_niri {}
    }
    Component {
        id: hyprlandWorkspacesComponent
        Workspaces_hyprland {}
    }

    Updater {}
    Pull {}
    Push {}
    Tray {}

    

}