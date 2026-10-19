pragma Singleton
import Quickshell
import QtQuick
import Niri
import qs.services

// niri's event stream (qml-niri) for the bar's workspaces. Only connects when
// the shell runs on niri.
Singleton {
    readonly property var workspaces: niri.workspaces
    function focusWorkspaceById(id) { niri.focusWorkspaceById(id) }

    property Niri niri: Niri {
        Component.onCompleted: if (Compositor.isNiri) connect()
        onConnected: console.info("Connected to niri")
        onErrorOccurred: error => console.error("Niri error:", error)
    }
}
