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
//   autostart  → programs started at login: { items: [{ id, name, cmd, enabled, on }] }
//   keybinds   → own / changed keybinds: { binds: [{ id, keys, name, kind, … }] }
//   syntax     → edited config templates / option paths (Syntax.qml)
//   icons      → changed icons { "<id>": "<glyph>" } (Icons.qml)
//   monitorsPage → monitors page options { identifyAt: "top-left" | … }
//   dashboard, controlCenter → which cards sit where (PanelLayout.qml)
//   bar, notifications, theme, audio, bluetooth, power, defaultApps,
//   clipboard, connections, capture, dotfiles, netTools, updates,
//   settingsProfiles, wizard, health, perfmon
//              → one group per feature (see PLAN.md); readers always have a
//                default, so an empty / old file never breaks anything
// "version" is the file format; migrate() brings older files up to date.
// (both compositors' override files are generated from niri / hyprland /
//  autostart / keybinds / syntax)
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
    property var autostart: ({})
    property var keybinds: ({})
    property var syntax: ({})
    property var bar: ({})
    property var notifications: ({})
    property var theme: ({})
    property var audio: ({})
    property var bluetooth: ({})
    property var power: ({})
    property var defaultApps: ({})
    property var clipboard: ({})
    property var connections: ({})
    property var capture: ({})
    property var dotfiles: ({})
    property var netTools: ({})
    property var updates: ({})
    property var settingsProfiles: ({})
    property var wizard: ({})
    property var health: ({})
    property var perfmon: ({})
    property var launcher: ({})
    property var icons: ({})
    property var monitorsPage: ({})
    property var dashboard: ({})
    property var controlCenter: ({})
    property bool loaded: false

    // every group, in the order they're written
    readonly property var groups: ["properties", "niri", "hyprland", "monitors", "calendar", "network",
                                   "battery", "profile", "autostart", "keybinds", "syntax",
                                   "bar", "notifications", "theme", "audio", "bluetooth", "power", "defaultApps",
                                   "clipboard", "connections", "capture", "dotfiles", "netTools", "updates",
                                   "settingsProfiles", "wizard", "health", "perfmon", "launcher", "icons", "monitorsPage",
                                   "dashboard", "controlCenter"]
    // how each group is called in the UI (export / import messages, profiles).
    // A new group needs: a property above, an entry in `groups`, a label here,
    // and a check in modules/settings/SettingsTransfer.qml (Health → settings.json
    // warns when the current settings wouldn't pass the import check)
    readonly property var groupLabels: ({ properties: "Appearance / bar / panels", niri: "niri", hyprland: "Hyprland",
        monitors: "Monitors", calendar: "Calendar", network: "Network page", battery: "Battery alerts", profile: "Profile",
        autostart: "Autostart", keybinds: "Keybinds", syntax: "Syntax", bar: "Bar layout", notifications: "Notifications",
        theme: "Theme", audio: "Audio", bluetooth: "Bluetooth", power: "Power", defaultApps: "Default apps",
        clipboard: "Clipboard", connections: "Connections", capture: "Screenshots", dotfiles: "Dotfiles",
        netTools: "Network tools", updates: "Updates", settingsProfiles: "Profiles", wizard: "First run",
        health: "Health check", perfmon: "Performance monitor", launcher: "Launcher", icons: "Icons",
        monitorsPage: "Monitors page", dashboard: "Dashboard layout", controlCenter: "Control center layout" })
    function groupLabel(g) { return groupLabels[g] ?? g }

    // ── File format ──────────────────────────────────────────────────────────
    // 1: no "version" field (everything up to now)
    // 2: "version" written; the feature groups above exist (empty = defaults)
    readonly property int version: 2
    function migrate(o) {
        let v = typeof o.version === "number" ? o.version : 1
        if (v < 2) v = 2          // 1 → 2: only new, optional groups; nothing to convert
        o.version = v
        return o
    }

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
            const o = migrate(text.trim() === "" ? {} : JSON.parse(text))
            // a group that isn't an object (hand edit) falls back to defaults
            for (const g of root.groups) root[g] = (o[g] !== null && typeof o[g] === "object" && !Array.isArray(o[g])) ? o[g] : {}
        } catch (e) {
            console.warn("settings.json is not valid JSON, using defaults:", e)
        }
        root.loaded = true
    }

    // sliders change values many times a second, so writes are batched
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            const o = { version: root.version }
            for (const g of root.groups) o[g] = root[g]
            file.setText(JSON.stringify(o, null, 2) + "\n")
        }
    }

    // no settings.json (or an empty one) when the shell started: a new install
    // (the first-run wizard opens then)
    property bool fresh: false
    Component.onCompleted: { const t = file.text() ?? ""; fresh = t.trim() === "" || t.trim() === "{}"; parse(t) }

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
