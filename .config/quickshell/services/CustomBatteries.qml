pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Batteries that UPower / BlueZ don't know about (e.g. a wireless headset
// read through its vendor app). Each entry either asks a local HTTP API
// (`url` + `pick(json)`, done in QML: no process every poll) or runs
// `command`, which must print a percentage (0–100). Anything else hides the
// entry until the next poll.
//
// Add more by appending to `sources`:
//   { name: "Mouse", icon: "󰍽", command: "some-cmd-printing-a-number" }
//   { name: "Pad", icon: "󰊴", url: "http://127.0.0.1:1234/state", pick: j => j.battery }
Singleton {
    id: root

    readonly property var sources: [
        {
            name: "HS80",
            icon: "󰋋",
            // iCUE-style bridge on localhost (was: curl | jq every 10 s)
            url: "http://127.0.0.1:27003/api/batteryStats",
            pick: j => j.data["1786e76c000400da"].Level
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

    // only a change is assigned: every reader (bar, control center,
    // lockscreen) re-evaluates on a new `levels` object
    function setLevel(name, v) {
        const ok = !isNaN(v) && v >= 0 && v <= 100
        if (ok ? levels[name] === v : levels[name] === undefined) return
        const next = Object.assign({}, levels)
        if (ok) next[name] = v
        else delete next[name]
        levels = next
    }

    function poll(src) {
        const x = new XMLHttpRequest()
        x.timeout = 2000
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            let v = NaN
            try { if (x.status === 200) v = parseInt(src.pick(JSON.parse(x.responseText))) } catch (e) {}
            root.setLevel(src.name, v)
        }
        x.open("GET", src.url)
        x.send()
    }

    function refresh() {
        for (const s of sources) if (s.url) poll(s)
        for (let i = 0; i < pollers.count; i++) pollers.objectAt(i).running = true
    }
    Component.onCompleted: refresh()

    Instantiator {
        id: pollers
        model: root.sources.filter(s => s.command)

        Process {
            required property var modelData
            command: ["bash", "-c", modelData.command]
            running: true
            stdout: StdioCollector {
                onStreamFinished: root.setLevel(modelData.name, parseInt(text.trim()))
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
