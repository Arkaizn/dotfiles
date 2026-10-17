pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// User settings changed in the settings app (modules/settings), stored in
// settings.json next to shell.qml:
//   { "properties": { key: value }, "niri": { key: value }, "hyprland": { key: value },
//     "monitors": { "<make model serial>": { mode, scale, ... } } }
// Only changed values are stored; everything else keeps its default.
//   properties → applied by Properties.qml (defaults = the values written there);
//                a color can also be { "wal": "color4", "alpha": 0.8 } to follow pywal
//   niri       → written to niri's override file by NiriSettings.qml
//   hyprland   → written to Hyprland's override file by HyprSettings.qml
//   monitors   → written to niri's / Hyprland's monitor file by Monitors.qml
//   calendar   → reminder / sync options, read by CalendarStore.qml
//   network    → network page preferences (hidden interfaces, safe apply)
//   battery    → low-battery notifications, read by BatteryAlerts.qml
//   profile    → display name + picture revision (dashboard, lockscreen)
Singleton {
    id: root

    readonly property string path: Quickshell.shellDir + "/settings.json"
    property var properties: ({})
    property var niri: ({})
    property var hyprland: ({})
    property var monitors: ({})
    property var calendar: ({})
    property var network: ({})
    property var battery: ({})
    property var profile: ({})
    property bool loaded: false

    function has(group, key) { return root[group][key] !== undefined }

    function set(group, key, value) {
        const m = Object.assign({}, root[group])
        m[key] = value
        root[group] = m
        saveTimer.restart()
    }

    function reset(group, key) {
        if (!has(group, key)) return
        const m = Object.assign({}, root[group])
        delete m[key]
        root[group] = m
        saveTimer.restart()
    }

    function setGroup(group, obj) {
        root[group] = obj
        saveTimer.restart()
    }

    function resetGroup(group) {
        root[group] = {}
        saveTimer.restart()
    }

    function parse(text) {
        // don't let the reload of an older write undo changes still waiting to be saved
        if (saveTimer.running) return
        try {
            const o = text.trim() === "" ? {} : JSON.parse(text)
            root.properties = o.properties ?? {}
            root.niri = o.niri ?? {}
            root.hyprland = o.hyprland ?? {}
            root.monitors = o.monitors ?? {}
            root.calendar = o.calendar ?? {}
            root.network = o.network ?? {}
            root.battery = o.battery ?? {}
            root.profile = o.profile ?? {}
        } catch (e) {
            console.warn("settings.json is not valid JSON, using defaults:", e)
        }
        root.loaded = true
    }

    // sliders change values many times a second, so writes are batched
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: file.setText(JSON.stringify({ properties: root.properties, niri: root.niri, hyprland: root.hyprland, monitors: root.monitors, calendar: root.calendar, network: root.network, battery: root.battery, profile: root.profile }, null, 2) + "\n")
    }

    Component.onCompleted: parse(file.text())

    FileView {
        id: file
        path: root.path
        watchChanges: true          // hand edits apply live too
        blockLoading: true          // first read is synchronous, so no defaults flash at startup
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.loaded = true   // no file yet = all defaults
    }
}
