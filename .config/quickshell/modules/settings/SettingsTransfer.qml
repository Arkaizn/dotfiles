import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "JsonCheck.js" as JsonCheck
import "Valid.js" as Valid

// Export / import of settings.json, plus the banner that reports on it.
//
// Export writes every group to a file picked with zenity. Import reads a
// file, checks all of it first (JSON syntax with line + column, then every
// group, key and value against the settings app's specs), and only after a
// clean check and a confirm replaces the groups that are in the file.
// Groups the file leaves out are kept.
Rectangle {
    id: root

    required property var pages              // SettingsWindow's pages (specs of shell/calendar keys)

    // "" hidden, "busy", "error", "confirm" (checked, waiting for Import), "done"
    property string mode: ""
    property string title: ""
    property string details: ""
    property var pending: null               // checked file content, while mode === "confirm"

    readonly property string defaultPath: Quickshell.env("HOME") + "/quickshell-settings.json"
    // every group of settings.json (one list: services/Settings.qml)
    readonly property var groups: Settings.groups
    readonly property var groupNames: ({ properties: "shell", niri: "niri", hyprland: "Hyprland", monitors: "monitors",
        calendar: "calendar", network: "network page", battery: "battery", profile: "profile", autostart: "autostart",
        keybinds: "keybinds", syntax: "syntax", bar: "bar layout", notifications: "notifications", theme: "theme",
        audio: "audio", bluetooth: "bluetooth", power: "power", defaultApps: "default apps", clipboard: "clipboard",
        connections: "connections", capture: "screenshots", dotfiles: "dotfiles", netTools: "network tools",
        updates: "updates", settingsProfiles: "settings profiles", wizard: "first-run", health: "health check",
        perfmon: "performance monitor", launcher: "launcher" })
    // feature groups: free-form objects, checked by their own validator if there is one
    readonly property var freeGroups: ["bar", "notifications", "theme", "audio", "bluetooth", "power", "defaultApps",
        "clipboard", "connections", "dotfiles", "netTools", "updates", "settingsProfiles", "wizard",
        "health"]
    // group → function(value, err) for the feature groups that need more than "is an object"
    property var validators: ({
        wizard: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k === "done") { if (typeof v[k] !== "boolean") err([k], "done must be true or false") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        settingsProfiles: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k === "active") { if (typeof v[k] !== "string" || (v[k] !== "" && SettingsProfiles.validName(v[k]) !== "")) err([k], "active is a profile name") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        updates: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k === "interval") { if (!Number.isInteger(v[k]) || v[k] < 0 || v[k] > 1440) err([k], "interval is 0–1440 minutes") }
                else if (k === "aur" || k === "notify") { if (typeof v[k] !== "boolean") err([k], k + " must be true or false") }
                else if (k === "mirrorCountries") { if (typeof v[k] !== "string" || !/^[A-Za-z ,]*$/.test(v[k])) err([k], "mirrorCountries: names or codes separated by commas") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        netTools: (v, err) => {
            for (const k of Object.keys(v)) {
                if (!["lastHost", "lastPortHost", "lastPort"].includes(k)) err([k], "unknown setting \"" + k + "\"")
                else if (typeof v[k] !== "string" || (v[k] !== "" && (k === "lastPort" ? Valid.port(v[k]) : Valid.host(v[k])) !== "")) err([k], k + " isn't a valid " + (k === "lastPort" ? "port" : "host"))
            }
        },
        power: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k === "batterySaver") { if (typeof v[k] !== "boolean") err([k], "batterySaver must be true or false") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        audio: (v, err) => {
            for (const k of Object.keys(v)) {
                const x = v[k]
                if (k === "step") { if (!Number.isInteger(x) || x < 1 || x > 20) err([k], "step is 1–20") }
                else if (k === "maxVolume") { if (!Number.isInteger(x) || x < 100 || x > 150) err([k], "maxVolume is 100–150") }
                else if (k === "sliderScroll") { if (typeof x !== "boolean") err([k], "sliderScroll must be true or false") }
                else if (k === "hidden") { if (!Array.isArray(x) || x.some(n => typeof n !== "string")) err([k], "hidden is a list of device names") }
                else if (k === "names") { if (!x || typeof x !== "object" || Array.isArray(x) || Object.values(x).some(n => typeof n !== "string")) err([k], "names is { device: \"name\" }") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        notifications: (v, err) => {
            const bools = ["dnd", "scheduleOn", "allowCritical"]
            for (const k of Object.keys(v)) {
                const x = v[k]
                if (bools.includes(k)) { if (typeof x !== "boolean") err([k], k + " must be true or false") }
                else if (k === "scheduleFrom" || k === "scheduleTo") { if (Notifs.minutesOf(x) < 0) err([k], k + " must be HH:MM") }
                else if (k === "position") { if (!["top-right", "top-center", "top-left", "bottom-right", "bottom-left"].includes(x)) err([k], "unknown position " + JSON.stringify(x)) }
                else if (k === "timeout") { if (!Number.isInteger(x) || x < 1 || x > 60) err([k], "timeout is 1–60 seconds") }
                else if (k === "maxPopups") { if (!Number.isInteger(x) || x < 1 || x > 10) err([k], "maxPopups is 1–10") }
                else if (k === "rules") {
                    if (!Array.isArray(x)) err([k], "rules must be a list")
                    else x.forEach((r, i) => {
                        if (!r || typeof r.app !== "string" || r.app.trim() === "") err([k], "rule " + (i + 1) + " needs an app")
                        else if (!["normal", "silent", "hide"].includes(r.action)) err([k], "rule " + (i + 1) + ": action is normal, silent or hide")
                    })
                }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        dotfiles: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k === "repo") { if (typeof v.repo !== "string" || v.repo.trim() === "") err(["repo"], "repo must be a path") }
                else if (k === "profile") { if (!["default", "full"].includes(v.profile)) err(["profile"], "profile is default or full") }
                else err([k], "unknown setting \"" + k + "\"")
            }
        },
        connections: (v, err) => {
            for (const k of Object.keys(v)) {
                if (k !== "list") { err([k], "unknown setting \"" + k + "\""); continue }
                if (!Array.isArray(v.list)) { err(["list"], "list must be a list"); continue }
                v.list.forEach((c, i) => {
                    if (!c || typeof c !== "object") return err(["list"], "entry " + (i + 1) + " isn't an object")
                    const e = RemoteConnections.validate(c)
                    for (const f of Object.keys(e)) err(["list"], "entry " + (i + 1) + " (" + (c.name ?? "?") + "): " + f + ": " + e[f])
                    if (Object.keys(c).some(f => /pass(word)?$/i.test(f) && f !== "password")
                        || (c.password !== undefined && !["none", "ask", "keyring"].includes(c.password)))
                        err(["list"], "entry " + (i + 1) + ": passwords can't be imported (only none / ask / keyring)")
                })
            }
        },
        bar: (v, err) => {
            const checkLayout = (l, path) => {
                if (!l || typeof l !== "object" || Array.isArray(l)) return err(path, "layout must be an object")
                for (const z of Object.keys(l)) {
                    if (!BarLayout.zones.includes(z)) { err(path.concat([z]), "unknown zone \"" + z + "\""); continue }
                    if (!Array.isArray(l[z])) { err(path.concat([z]), z + " must be a list"); continue }
                    for (const id of l[z]) if (!BarLayout.moduleIds.includes(id)) err(path.concat([z]), "unknown module \"" + id + "\"")
                }
            }
            for (const k of Object.keys(v)) {
                if (k === "layout") checkLayout(v.layout, ["layout"])
                else if (k === "monitors") {
                    if (!v.monitors || typeof v.monitors !== "object" || Array.isArray(v.monitors)) err(["monitors"], "monitors must be an object")
                    else for (const m of Object.keys(v.monitors)) checkLayout(v.monitors[m], ["monitors", m])
                } else err([k], "unknown setting \"" + k + "\"")
            }
        }
    })
    // the network page's own preferences (not spec-driven)
    readonly property var networkSpecs: ({
        hideVirtual: { type: "bool" }, safeApply: { type: "bool" },
        showDevices: { type: "list" }, hideDevices: { type: "list" },
        hosts: { type: "objects" }          // [{ id, ip, names, enabled }]
    })
    readonly property var walNames: ["foreground", "background", "color0", "color1", "color2", "color3", "color4",
        "color5", "color6", "color7", "color8", "color9", "color10", "color11", "color12", "color13", "color14", "color15"]

    function show(m, t, d) { mode = m; title = t; details = d ?? "" }
    function dismiss() { mode = ""; pending = null }

    // ── Export ───────────────────────────────────────────────────────────────
    function exportSettings() {
        pick.forImport = false
        pick.command = ["zenity", "--file-selection", "--save", "--title=Export Quickshell settings",
                        "--filename=" + defaultPath, "--file-filter=JSON | *.json", "--file-filter=All files | *"]
        pick.running = true
    }

    function writeTo(path) {
        const o = { quickshellSettings: 1, exported: new Date().toISOString(), version: Settings.version }
        for (const g of groups) o[g] = Settings[g]
        writer.path = path
        writer.command = ["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", JSON.stringify(o, null, 2) + "\n", path]
        show("busy", "Exporting…")
        writer.running = true
    }

    // ── Import ───────────────────────────────────────────────────────────────
    function importSettings() {
        pick.forImport = true
        pick.command = ["zenity", "--file-selection", "--title=Import Quickshell settings",
                        "--filename=" + Quickshell.env("HOME") + "/", "--file-filter=JSON | *.json", "--file-filter=All files | *"]
        pick.running = true
    }

    function readFrom(path) {
        reader.path = path
        reader.command = ["cat", "--", path]
        show("busy", "Checking " + path + "…")
        reader.running = true
    }

    function check(text, path) {
        const name = path.replace(/.*\//, "")
        let parsed
        try {
            parsed = JsonCheck.parse(text)
        } catch (e) {
            if (e.line === undefined) throw e
            show("error", name + " isn't valid JSON, nothing was imported",
                 "line " + e.line + ", column " + e.col + ": " + e.message + "\n" + excerpt(text, e.line, e.col))
            return
        }
        const errors = validate(parsed.value, parsed.lines)
        if (errors.length > 0) {
            errors.sort((a, b) => a.line - b.line)
            const shown = errors.slice(0, 12).map(e => (e.line ? "line " + e.line + ": " : "") + e.message)
            if (errors.length > 12) shown.push("… and " + (errors.length - 12) + " more")
            show("error", name + " has " + errors.length + (errors.length === 1 ? " problem" : " problems")
                 + ", nothing was imported", shown.join("\n"))
            return
        }
        const v = parsed.value
        const parts = groups.filter(g => v[g] !== undefined)
            .map(g => Object.keys(v[g]).length + " " + groupNames[g])
        if (parts.length === 0) {
            show("error", name + " has no settings in it, nothing was imported",
                 "Expected at least one of: " + groups.map(g => "\"" + g + "\"").join(", "))
            return
        }
        pending = v
        show("confirm", name + " is valid: " + parts.join(", "),
             "Importing replaces your current " + groups.filter(g => v[g] !== undefined).map(g => groupNames[g]).join(", ")
             + " settings with the ones in the file.")
    }

    // the line with the error and a ^ under the spot
    function excerpt(text, line, col) {
        const l = (text.split("\n")[line - 1] ?? "").replace(/\t/g, " ")
        const start = Math.max(0, col - 50)
        return "  " + l.substr(start, 90) + "\n  " + " ".repeat(Math.max(0, col - 1 - start)) + "^"
    }

    function apply() {
        const v = pending
        dismiss()
        for (const g of groups) if (v[g] !== undefined) Settings.setGroup(g, v[g])
        if (v.monitors !== undefined) Monitors.write()     // niri / Hyprland settings follow Settings.niri / .hyprland by themselves
        show("done", "Settings imported")
    }

    // ── Checks ───────────────────────────────────────────────────────────────
    // returns [{ line, message }]; line is the line of the key in the file
    function validate(v, lines) {
        const errors = []
        const at = path => lines[JSON.stringify(path)] ?? 0
        const err = (path, msg) => errors.push({ line: at(path), message: msg })
        const isObj = x => x !== null && typeof x === "object" && !Array.isArray(x)

        if (!isObj(v)) return [{ line: 1, message: "the file should be one { … } object" }]

        for (const g of Object.keys(v)) {
            if (g === "quickshellSettings" || g === "exported" || g === "version") continue
            if (!groups.includes(g)) { err([g], "unknown group \"" + g + "\" (expected " + groups.join(", ") + ")"); continue }
            if (!isObj(v[g])) { err([g], "\"" + g + "\" should be an object { … }"); continue }
            if (g === "monitors") { checkMonitors(v[g], err); continue }
            if (g === "autostart" || g === "keybinds" || g === "syntax") { checkLists(g, v[g], err); continue }
            if (freeGroups.includes(g)) { if (validators[g]) validators[g](v[g], (path, msg) => err([g].concat(path), g + ": " + msg)); continue }
            for (const k of Object.keys(v[g])) {
                const sp = specFor(g, k)
                if (!sp) { err([g, k], g + ": unknown setting \"" + k + "\""); continue }
                const problem = checkValue(sp, v[g][k], g === "properties")
                if (problem) err([g, k], g + "." + k + ": " + problem)
            }
        }
        return errors
    }

    function specFor(group, key) {
        if (group === "niri") return NiriSettings.spec(key)
        if (group === "hyprland") return HyprSettings.spec(key)
        if (group === "network") return networkSpecs[key] ?? null
        if (group === "profile") return ({ name: { type: "string" }, faceRev: { type: "real" } })[key] ?? null
        for (const p of pages)
            if (p.store === group)
                for (const s of p.sections) for (const i of s.items) if (i.key === key) return i
        return null
    }

    function str(x) { return JSON.stringify(x) }

    function checkValue(sp, x, canLink) {
        const num = typeof x === "number" && isFinite(x)
        const range = () => {
            if (sp.min !== undefined && x < sp.min) return str(x) + " is below the minimum " + sp.min
            if (sp.max !== undefined && x > sp.max) return str(x) + " is above the maximum " + sp.max
            return ""
        }
        switch (sp.type) {
        case "int":
            if (!num || !Number.isInteger(x)) return "expected a whole number, got " + str(x)
            return range()
        case "real":
            if (!num) return "expected a number, got " + str(x)
            return range()
        case "bool":
            return typeof x === "boolean" ? "" : "expected true or false, got " + str(x)
        case "objects":
            return Array.isArray(x) && x.every(v => v !== null && typeof v === "object" && !Array.isArray(v)) ? "" : "expected a list of { … } entries, got " + str(x)
        case "list":
            return Array.isArray(x) && x.every(v => typeof v === "string") ? "" : "expected a list of names like [\"docker0\"], got " + str(x)
        case "choice":
            return sp.options.includes(x) ? "" : str(x) + " isn't one of " + sp.options.map(str).join(", ")
        case "color":
            if (typeof x === "string")
                return /^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(x) ? "" : str(x) + " isn't a color (#rrggbb or #aarrggbb)"
            if (canLink && x !== null && typeof x === "object" && "wal" in x) {
                if (Object.keys(x).some(k => k !== "wal" && k !== "alpha")) return "a pywal link only has \"wal\" and \"alpha\""
                if (!walNames.includes(x.wal)) return str(x.wal) + " isn't a pywal color (foreground, background, color0 … color15)"
                if (x.alpha !== undefined && !(typeof x.alpha === "number" && x.alpha >= 0 && x.alpha <= 1))
                    return "alpha should be a number from 0 to 1, got " + str(x.alpha)
                return ""
            }
            return "expected a color like \"#ff8800\"" + (canLink ? " or { \"wal\": \"color4\" }" : "") + ", got " + str(x)
        default:   // string, font
            return typeof x === "string" ? "" : "expected text in quotes, got " + str(x)
        }
    }

    // autostart.items / keybinds.binds / syntax.templates + paths: just the shape
    function checkLists(g, o, err) {
        const isObj = x => x !== null && typeof x === "object" && !Array.isArray(x)
        if (g === "syntax") {
            for (const k of Object.keys(o)) {
                if (!["templates", "words", "paths"].includes(k)) { err([g, k], "syntax: unknown part \"" + k + "\""); continue }
                if (!isObj(o[k]) || Object.values(o[k]).some(x => typeof x !== "string"))
                    err([g, k], "syntax." + k + ": expected { name: \"text\" }")
            }
            return
        }
        const listKey = g === "autostart" ? "items" : "binds"
        for (const k of Object.keys(o)) {
            if (k !== listKey) { err([g, k], g + ": unknown part \"" + k + "\""); continue }
            if (!Array.isArray(o[k])) { err([g, k], g + "." + k + ": expected a list"); continue }
            o[k].forEach((e, i) => {
                if (!isObj(e)) { err([g, k, i], g + "." + k + "[" + i + "]: expected an object"); return }
                if (g === "autostart" && typeof e.cmd !== "string") err([g, k, i], "autostart: entry " + (i + 1) + " needs a \"cmd\" text")
                if (g === "keybinds" && (!Array.isArray(e.keys) || e.keys.some(x => typeof x !== "string")))
                    err([g, k, i], "keybinds: entry " + (i + 1) + " needs \"keys\" like [\"Mod\", \"T\"]")
                if (g === "keybinds" && !["command", "original", "disable"].includes(e.kind))
                    err([g, k, i], "keybinds: entry " + (i + 1) + " has an unknown kind " + str(e.kind))
            })
        }
    }

    // monitors: { "<make model serial>": { name, enabled, mode, scale, transform, x, y, vrr } }
    function checkMonitors(m, err) {
        const fields = { name: "string", enabled: "boolean", mode: "string", scale: "number",
                         transform: "string", x: "number", y: "number", vrr: "boolean" }
        const transforms = ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]
        for (const id of Object.keys(m)) {
            const c = m[id]
            const p = ["monitors", id]
            if (c === null || typeof c !== "object" || Array.isArray(c)) { err(p, "monitor \"" + id + "\" should be an object { … }"); continue }
            for (const f of Object.keys(fields)) {
                if (c[f] === undefined) { err(p, "monitor \"" + id + "\" is missing \"" + f + "\""); continue }
                if (typeof c[f] !== fields[f] || (fields[f] === "number" && !isFinite(c[f])))
                    err(p.concat(f), "monitors." + f + ": expected " + (fields[f] === "boolean" ? "true or false" : "a " + fields[f]) + ", got " + str(c[f]))
            }
            for (const f of Object.keys(c))
                if (!(f in fields)) err(p.concat(f), "monitor \"" + id + "\": unknown field \"" + f + "\"")
            if (typeof c.mode === "string" && !/^\d+x\d+(@[\d.]+)?$/.test(c.mode))
                err(p.concat("mode"), "monitors.mode: " + str(c.mode) + " should look like \"2560x1440@143.973\"")
            if (typeof c.scale === "number" && !(c.scale > 0 && c.scale <= 10))
                err(p.concat("scale"), "monitors.scale: " + c.scale + " should be above 0 and at most 10")
            if (typeof c.transform === "string" && !transforms.includes(c.transform))
                err(p.concat("transform"), "monitors.transform: " + str(c.transform) + " isn't one of " + transforms.join(", "))
            for (const f of ["x", "y"])
                if (typeof c[f] === "number" && !Number.isInteger(c[f]))
                    err(p.concat(f), "monitors." + f + ": expected a whole number, got " + c[f])
        }
    }

    // ── Processes ────────────────────────────────────────────────────────────
    Process {
        id: pick
        property bool forImport: false
        stdout: StdioCollector { id: pickOut }
        onExited: code => {
            const path = pickOut.text.trim()
            if (code === 0 && path !== "") {
                if (forImport) root.readFrom(path)
                else root.writeTo(path)
            } else if (code !== 1) {                // 1 = cancelled
                root.show("error", "Couldn't open the file picker",
                          code === 127 ? "zenity isn't installed." : "zenity exited with code " + code + ".")
            }
        }
    }

    Process {
        id: writer
        property string path: ""
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            if (code === 0) root.show("done", "Settings exported to " + writer.path)
            else root.show("error", "Couldn't export the settings", writeErr.text.trim())
        }
    }

    Process {
        id: reader
        property string path: ""
        stdout: StdioCollector { id: readOut }
        stderr: StdioCollector { id: readErr }
        onExited: code => {
            if (code === 0) root.check(readOut.text, reader.path)
            else root.show("error", "Couldn't read " + reader.path, readErr.text.trim())
        }
    }

    // "done" goes away by itself
    Timer {
        running: root.mode === "done"
        interval: 4000
        onTriggered: root.dismiss()
    }

    // ── Banner ───────────────────────────────────────────────────────────────
    readonly property color tint: mode === "error" ? Qt.rgba(0.95, 0.55, 0.66, 1) : Colors.color6

    visible: mode !== ""
    implicitHeight: body.implicitHeight + 20
    radius: 14
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.12)
    border.width: Properties.panelBorderWidth
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.35)

    RowLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: 14
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            text: root.mode === "error" ? "󰀦" : root.mode === "confirm" ? "󰄬" : root.mode === "busy" ? "󰔟" : "󰄴"
            color: root.mode === "error" ? "#f38ba8" : Colors.color6
            font.pixelSize: 18
            font.family: Properties.fontFamily
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: root.title
                color: "white"
                font.pixelSize: 12
                font.bold: true
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.details
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }

        ActionButton {
            Layout.alignment: Qt.AlignTop
            visible: root.mode === "confirm"
            text: "Import"
            icon: "󰋺"
            primary: true
            onClicked: root.apply()
        }
        IconButton {
            Layout.alignment: Qt.AlignTop
            visible: root.mode !== "busy"
            icon: "󰅖"
            tooltip: root.mode === "confirm" ? "Cancel" : "Dismiss"
            onClicked: root.dismiss()
        }
    }
}
