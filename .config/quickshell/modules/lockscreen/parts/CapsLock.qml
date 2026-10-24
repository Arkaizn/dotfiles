import Quickshell
import Quickshell.Io
import QtQuick

// Caps Lock from the keyboard LEDs (any keyboard), polled every 250 ms while
// `active` (/sys/class/leds is readable by everyone, so the login screen can
// use it too).
Scope {
    id: root

    property bool active: false
    property bool on: false

    Process {
        id: proc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.on = text.split("\n").some(l => parseInt(l) > 0)
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }
}
