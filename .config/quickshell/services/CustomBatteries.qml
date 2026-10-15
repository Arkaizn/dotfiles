pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Batteries that UPower / BlueZ don't know about (e.g. a wireless headset
// read through its vendor app). Each entry runs `command`, which must print
// a percentage (0–100); anything else hides the entry until the next poll.
//
// Add more by appending to `sources`:
//   { name: "Mouse", icon: "󰍽", command: "some-cmd-printing-a-number" }
Singleton {
    id: root

    readonly property var sources: [
        {
            name: "HS80",
            icon: "󰋋",
            command: "curl -s -m 2 http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"
        }
    ]

    // name -> level (int), only for sources that currently report one
    property var levels: ({})

    // [{ name, icon, level }] for the sources that have a value right now
    readonly property var available: sources
        .filter(s => levels[s.name] !== undefined)
        .map(s => ({ name: s.name, icon: s.icon, level: levels[s.name] }))

    function levelOf(name) {
        return levels[name] ?? -1
    }

    function refresh() {
        for (let i = 0; i < pollers.count; i++) pollers.objectAt(i).running = true
    }

    Instantiator {
        id: pollers
        model: root.sources

        Process {
            required property var modelData
            command: ["bash", "-c", modelData.command]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const v = parseInt(text.trim())
                    const next = Object.assign({}, root.levels)
                    if (isNaN(v) || v < 0 || v > 100) delete next[modelData.name]
                    else next[modelData.name] = v
                    root.levels = next
                }
            }
        }
    }

    Timer {
        interval: 10000 // battery levels change slowly
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
