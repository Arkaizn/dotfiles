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
    // the monitor with the focused workspace, from the stream ("" if unknown)
    function focusedOutput() {
        if (!niri.isConnected()) return ""
        const ws = niri.workspaces
        for (let i = 0; i < (ws?.count ?? 0); i++) {
            const w = ws.get(i)
            if (w?.isFocused || w?.is_focused) return w.output ?? ""
        }
        return ""
    }

    property Niri niri: Niri {
        Component.onCompleted: if (Compositor.isNiri) connect()
        onConnected: console.info("Connected to niri")
        onErrorOccurred: error => console.error("Niri error:", error)
    }
}
