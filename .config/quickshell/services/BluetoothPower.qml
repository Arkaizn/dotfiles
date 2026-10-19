pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick

// Bluetooth on/off that also handles rfkill. BlueZ refuses to power on a
// soft-blocked adapter (state "Blocked"), so unblock first, then power on.
// Also the shared device helpers: what's connected, and an icon per kind of
// device (headset, controller, mouse, …) for the bar, control center,
// lockscreen and settings.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool blocked: adapter?.state === BluetoothAdapterState.Blocked
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var connected: (adapter?.devices?.values ?? []).filter(d => d.connected)

    // BlueZ's icon name (freedesktop style, e.g. "audio-headset") → glyph
    function iconFor(d) {
        const i = d?.icon || ""
        if (i.includes("headset") || i.includes("headphone")) return Icons.get("btHeadset")
        if (i.includes("audio")) return Icons.get("btSpeaker")
        if (i.includes("gaming") || i.includes("joystick")) return Icons.get("btController")
        if (i.includes("mouse")) return Icons.get("btMouse")
        if (i.includes("keyboard")) return Icons.get("btKeyboard")
        if (i.includes("tablet")) return Icons.get("btTablet")
        if (i.includes("phone")) return Icons.get("btPhone")
        if (i.includes("watch")) return Icons.get("btWatch")
        if (i.includes("computer")) return Icons.get("btComputer")
        if (i.includes("printer")) return Icons.get("btPrinter")
        if (i.includes("camera")) return Icons.get("btCamera")
        return Icons.get("btOn")
    }
    // battery in %, -1 when the device doesn't report one
    function battery(d) { return d?.batteryAvailable ? Math.round(d.battery * 100) : -1 }

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
