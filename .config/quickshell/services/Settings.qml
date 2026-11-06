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
//   mail       → checking / notification / reading options, read by MailStore.qml
//   network    → network page preferences (hidden interfaces, safe apply)
//   battery    → low-battery notifications, read by BatteryAlerts.qml
//   profile    → display name + picture revision (dashboard, lockscreen)
//   autostart  → programs started at login: { items: [{ id, name, cmd, enabled, on }] }
//   keybinds   → own / changed keybinds: { binds: [{ id, keys, name, kind, … }] }
//   syntax     → edited config templates / option paths (Syntax.qml)
//   icons      → changed icons { "<id>": "<glyph>" } (Icons.qml)
//   monitorsPage → monitors page options { identifyAt: "top-left" | … }
//   dashboard, controlCenter → which cards sit where (PanelLayout.qml)
//   greeter    → the login screen (greeter/): follows the lockscreen or has
//                its own items, default user / session (LockItems.resolveGreeter);
//                copied to /var/lib/quickshell-greeter by GreeterSync.qml
//   zoom       → how big each app window draws (AppZoom.qml): { mail: "125", … } in %
//   media      → { bridge: bool } use the mediasync bridge for the bar and
//                dashboard (MediaSync.qml); its own settings live in the bridge
//   files      → the file manager (files.qml, its own process): keys and
//                checks in services/lib/FmSettings.js
//   bar, notifications, theme, audio, bluetooth, power, defaultApps,
//   clipboard, connections, capture, dotfiles, netTools, updates,
//   settingsProfiles, wizard, health, perfmon
//              → one group per feature (see PLAN.md); readers always have a
//                default, so an empty / old file never breaks anything
// QS_SETTINGS_FILE replaces the path (the login screen reads its copy).
// remote: the file manager's process (files.qml sets it, or QS_SETTINGS_REMOTE=1).
// It never writes the file: set / reset / setGroup / resetGroup change its copy
// and hand the change to the main shell (qs ipc call settingsStore apply,
// services/SettingsStore.qml), the one writer. When no main shell is running,
// it merges just those keys into the file itself.
// "version" is the file format; migrate() brings older files up to date.
// (both compositors' override files are generated from niri / hyprland /
//  autostart / keybinds / syntax)
Singleton {
    id: root

    readonly property string path: Quickshell.env("QS_SETTINGS_FILE") || Quickshell.shellDir + "/settings.json"
    property var properties: ({})
    property var niri: ({})
    property var hyprland: ({})
    property var monitors: ({})
    property var calendar: ({})
    property var mail: ({})
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
    property var lockscreen: ({})
    property var desktopWidgets: ({})
    property var media: ({})
    property var greeter: ({})
    property var panels: ({})
    property var zoom: ({})
    property var iconColors: ({})
    property var files: ({})
    property bool loaded: false
    property bool remote: Quickshell.env("QS_SETTINGS_REMOTE") === "1"

    // every group, in the order they're written
    readonly property var groups: ["properties", "niri", "hyprland", "monitors", "calendar", "mail", "network",
                                   "battery", "profile", "autostart", "keybinds", "syntax",
                                   "bar", "notifications", "theme", "audio", "bluetooth", "power", "defaultApps",
                                   "clipboard", "connections", "capture", "dotfiles", "netTools", "updates",
                                   "settingsProfiles", "wizard", "health", "perfmon", "launcher", "icons", "monitorsPage",
                                   "dashboard", "controlCenter", "lockscreen", "desktopWidgets", "media", "greeter", "panels", "zoom", "iconColors", "files"]
    // how each group is called in the UI (export / import messages, profiles).
    // A new group needs: a property above, an entry in `groups`, a label here,
    // and a check in modules/settings/SettingsTransfer.qml (Health → settings.json
    // warns when the current settings wouldn't pass the import check)
    readonly property var groupLabels: ({ properties: "Appearance / bar / panels", niri: "niri", hyprland: "Hyprland",
        monitors: "Monitors", calendar: "Calendar", mail: "Mail", network: "Network page", battery: "Battery alerts", profile: "Profile",
        autostart: "Autostart", keybinds: "Keybinds", syntax: "Syntax", bar: "Bar layout", notifications: "Notifications",
        theme: "Theme", audio: "Audio", bluetooth: "Bluetooth", power: "Power", defaultApps: "Default apps",
        clipboard: "Clipboard", connections: "Connections", capture: "Screenshots", dotfiles: "Dotfiles",
        netTools: "Network tools", updates: "Updates", settingsProfiles: "Profiles", wizard: "First run",
        health: "Health check", perfmon: "Performance monitor", launcher: "Launcher", icons: "Icons",
        monitorsPage: "Monitors page", dashboard: "Dashboard layout", controlCenter: "Control center layout",
        lockscreen: "Lockscreen", desktopWidgets: "Desktop widgets", media: "Media sources", greeter: "Login screen", panels: "Panels (size, place, bar edge)", zoom: "App zoom", iconColors: "Icon colors", files: "Files" })
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
        _queue(group, key, true, value)
        saveTimer.restart()
    }

    function reset(group, key) {
        if (!has(group, key)) return
        const m = Object.assign({}, root[group])
        delete m[key]
        root[group] = m
        _queue(group, key, false)
        saveTimer.restart()
    }

    function setGroup(group, obj) {
        if (remote) {           // key by key, so the main shell can check each one
            for (const k of Object.keys(root[group])) if (!(k in obj)) reset(group, k)
            for (const k of Object.keys(obj)) set(group, k, obj[k])
            return
        }
        root[group] = obj
        saveTimer.restart()
    }

    function resetGroup(group) {
        if (remote) { for (const k of Object.keys(root[group])) reset(group, k); return }
        root[group] = {}
        saveTimer.restart()
    }

    // remote mode: changes waiting for the next batch { group: { set: {k: v}, reset: [k] } }
    property var _outbox: ({})
    property bool _missed: false
    function _queue(group, key, isSet, value) {
        if (!remote) return
        const b = _outbox[group] ?? (_outbox[group] = { set: {}, reset: [] })
        if (isSet) { b.set[key] = value; b.reset = b.reset.filter(k => k !== key) }
        else { delete b.set[key]; if (!b.reset.includes(key)) b.reset.push(key) }
    }
    function _send() {
        if (sendProc.running) { saveTimer.restart(); return }
        const batch = _outbox
        _outbox = {}
        if (Object.keys(batch).length === 0) return
        const json = JSON.stringify(batch)
        sendProc.batch = batch
        sendProc.command = ["qs", "ipc", "-p", Quickshell.shellDir, "call", "settingsStore", "apply", json]
        sendProc.running = true
    }
    // no main shell to take it: merge only these keys into the file (read, change, write)
    function _writeOwn(batch) {
        let o = {}
        try { const t = file.text() ?? ""; o = t.trim() === "" ? {} : JSON.parse(t) } catch (e) { console.warn("settings.json is not valid JSON, not writing:", e); return }
        o = migrate(o)
        for (const g of Object.keys(batch)) {
            const m = (o[g] !== null && typeof o[g] === "object" && !Array.isArray(o[g])) ? o[g] : {}
            for (const k of Object.keys(batch[g].set)) m[k] = batch[g].set[k]
            for (const k of batch[g].reset) delete m[k]
            o[g] = m
        }
        file.setText(JSON.stringify(o, null, 2) + "\n")
    }

    function parse(text) {
        // don't let the reload of an older write undo changes still waiting to be saved
        if (saveTimer.running) return
        if (sendProc.running) { _missed = true; return }     // read again once it's sent
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
            if (root.remote) { root._send(); return }
            const o = { version: root.version }
            for (const g of root.groups) o[g] = root[g]
            file.setText(JSON.stringify(o, null, 2) + "\n")
        }
    }

    // remote mode: one batch at a time; what came in meanwhile goes in the next
    Process {
        id: sendProc
        property var batch: ({})
        stdout: StdioCollector { id: sendOut }
        stderr: StdioCollector { id: sendErr }
        onExited: code => {
            const answer = sendOut.text.trim()
            // (qs prints "No running instances …" on stdout or stderr, depending on the version)
            if (code !== 0 && (answer + sendErr.text).includes("No running instances")) root._writeOwn(batch)
            else if (answer !== "ok") console.warn("settings: the main shell didn't take", JSON.stringify(batch), "-", (answer || sendErr.text.trim()).split("\n")[0])
            if (root._missed) { root._missed = false; file.reload() }
            if (Object.keys(root._outbox).length > 0) saveTimer.restart()
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
