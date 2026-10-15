pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick

// Bluetooth on/off that also handles rfkill. BlueZ refuses to power on a
// soft-blocked adapter (state "Blocked"), so unblock first, then power on.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool blocked: adapter?.state === BluetoothAdapterState.Blocked
    readonly property bool enabled: adapter?.enabled ?? false

    function toggle() {
        if (enabled) setEnabled(false)
        else setEnabled(true)
    }

    function setEnabled(on) {
        if (!on) {
            if (adapter) adapter.enabled = false
            return
        }
        if (adapter && !blocked) {
            adapter.enabled = true
            return
        }
        unblockProc.running = true
    }

    Process {
        id: unblockProc
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: powerOnTimer.restart()
    }

    // give BlueZ a moment to notice the unblock before powering on
    Timer {
        id: powerOnTimer
        interval: 400
        onTriggered: if (root.adapter) root.adapter.enabled = true
    }
}
