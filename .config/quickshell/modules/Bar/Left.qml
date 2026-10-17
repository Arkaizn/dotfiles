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

    // Workspaces_niri for niri, Workspaces_hyprland for Hyprland
    Loader {
        sourceComponent: Compositor.isNiri ? niriWorkspacesComponent
                       : Compositor.isHyprland ? hyprlandWorkspacesComponent
                       : null
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