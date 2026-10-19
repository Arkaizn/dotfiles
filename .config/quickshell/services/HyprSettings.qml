pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Hyprland side of the settings app (same API as NiriSettings).
//
// Changed values (Settings.hyprland) are written to an override file,
// ~/.config/hypr/quickshell.lua, which hyprland.lua loads last
// (includeLine), so it wins over the hand-written files without touching
// them. Every write is checked with `Hyprland --verify-config` first, then
// Hyprland reloads. The file also loads the monitor setup from the Monitors
// page (quickshell-monitors.lua, written by Monitors.qml).
//
// Unchanged values are shown as Hyprland currently has them
// (`hyprctl getoption`). Only the Lua config (Hyprland 0.55+) is supported.
Singleton {
    id: root

    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME") ?? ""
        return (xdg !== "" ? xdg : Quickshell.env("HOME") + "/.config") + "/hypr"
    }
    readonly property string mainConfig: configDir + "/hyprland.lua"
    readonly property string overridePath: configDir + "/quickshell.lua"
    readonly property string monitorsPath: configDir + "/quickshell-monitors.lua"
    readonly property string includeLine: 'pcall(dofile, os.getenv("HOME") .. "/.config/hypr/quickshell.lua")'

    readonly property string windowTitle: NiriSettings.windowTitle

    property var effective: ({})     // key → value Hyprland currently uses
    property bool included: false    // hyprland.lua loads the override file
    property bool available: false   // there is a Lua config to add to
    property bool legacyConfig: false // only hyprland.conf (hyprlang): not supported
    property string error: ""
    property bool applying: false

    // ── What can be changed ──────────────────────────────────────────────────
    //   path: the option, as in hl.config / `hyprctl getoption`
    //   def:  Hyprland's default
    //   map:  choices stored by name, written as their index (follow_mouse)
    readonly property var schema: [
        { key: "layout", path: "general.layout", type: "choice", def: "dwindle",
          options: ["dwindle", "master", "scrolling", "monocle"],
          label: "Layout", desc: "How tiled windows are arranged" },
        { key: "gapsIn", path: "general.gaps_in", type: "int", def: 5, min: 0, max: 60,
          label: "Gaps between windows" },
        { key: "gapsOut", path: "general.gaps_out", type: "int", def: 20, min: 0, max: 80,
          label: "Gaps to screen edges" },
        { key: "rounding", path: "decoration.rounding", type: "int", def: 0, min: 0, max: 20,
          label: "Window corner radius", desc: "Rounded corners of every window" },
        { key: "roundingPower", path: "decoration.rounding_power", type: "real", def: 2, min: 2, max: 10, step: 0.5,
          label: "Corner shape", desc: "2 is a circle, higher is more squircle" },

        { key: "borderSize", path: "general.border_size", type: "int", def: 1, min: 0, max: 20,
          label: "Border width" },
        { key: "activeBorder", path: "general.col.active_border", type: "color", def: "#ffffffff",
          label: "Active border", desc: "Replaces a gradient with one color" },
        { key: "inactiveBorder", path: "general.col.inactive_border", type: "color", def: "#ff444444",
          label: "Inactive border" },
        { key: "activeOpacity", path: "decoration.active_opacity", type: "real", def: 1, min: 0.1, max: 1, step: 0.05,
          label: "Focused window opacity" },
        { key: "inactiveOpacity", path: "decoration.inactive_opacity", type: "real", def: 1, min: 0.1, max: 1, step: 0.05,
          label: "Other windows opacity" },
        { key: "dimInactive", path: "decoration.dim_inactive", type: "bool", def: false,
          label: "Dim other windows" },
        { key: "dimStrength", path: "decoration.dim_strength", type: "real", def: 0.5, min: 0, max: 1, step: 0.05,
          label: "Dim strength" },

        { key: "shadowOn", path: "decoration.shadow.enabled", type: "bool", def: true,
          label: "Shadows", desc: "Drop shadow under windows" },
        { key: "shadowRange", path: "decoration.shadow.range", type: "int", def: 4, min: 0, max: 100, label: "Size" },
        { key: "shadowPower", path: "decoration.shadow.render_power", type: "int", def: 3, min: 1, max: 4,
          label: "Falloff", desc: "Higher fades out faster" },
        { key: "shadowColor", path: "decoration.shadow.color", type: "color", def: "#ee1a1a1a", label: "Color" },

        { key: "animationsOn", path: "animations.enabled", type: "bool", def: true,
          label: "Animations", desc: "Window, workspace and layer animations" },
        { key: "blurOn", path: "decoration.blur.enabled", type: "bool", def: true,
          label: "Blur", desc: "Behind transparent windows and the shell" },
        { key: "blurSize", path: "decoration.blur.size", type: "int", def: 8, min: 1, max: 30,
          label: "Blur size", desc: "How far the blur spreads" },
        { key: "blurPasses", path: "decoration.blur.passes", type: "int", def: 1, min: 1, max: 8,
          label: "Blur passes", desc: "More passes = smoother blur" },
        { key: "blurVibrancy", path: "decoration.blur.vibrancy", type: "real", def: 0.1696, min: 0, max: 1, step: 0.05,
          label: "Vibrancy", desc: "Saturation of the blurred colors" },
        { key: "blurXray", path: "decoration.blur.xray", type: "bool", def: false,
          label: "X-ray", desc: "Floating windows blur only the wallpaper" },

        { key: "kbLayout", path: "input.kb_layout", type: "string", def: "us",
          label: "Keyboard layout", desc: "XKB layout(s), e.g. \"ch\" or \"us,de\"" },
        { key: "numlock", path: "input.numlock_by_default", type: "bool", def: false,
          label: "Numlock on startup" },
        { key: "sensitivity", path: "input.sensitivity", type: "real", def: 0, min: -1, max: 1, step: 0.05,
          label: "Pointer speed" },
        { key: "accelProfile", path: "input.accel_profile", type: "choice", def: "adaptive",
          options: ["adaptive", "flat"], label: "Pointer acceleration", desc: "Flat = no acceleration" },
        { key: "followMouse", path: "input.follow_mouse", type: "choice", def: "follow",
          options: ["disabled", "follow", "detached", "separate"], map: true,
          label: "Focus follows mouse", desc: "Whether moving the pointer focuses windows" },
        { key: "naturalScroll", path: "input.touchpad.natural_scroll", type: "bool", def: false,
          label: "Touchpad natural scrolling" },
        { key: "scrollFactor", path: "input.touchpad.scroll_factor", type: "real", def: 1, min: 0.05, max: 2, step: 0.05,
          label: "Touchpad scroll speed" }
    ]

    function spec(key) { return schema.find(s => s.key === key) }
    // option path, unless changed on the Syntax page
    function pathOf(s) { return Syntax.path("hyprland", s.key, s.path) }

    // corner radius of the shell's app windows: Hyprland's window rounding, 12 if 0
    readonly property int appRadius: {
        const v = Settings.hyprland.rounding ?? effective.rounding
        return v !== undefined && v > 0 ? Math.round(v) : 12
    }

    function value(key) {
        const o = Settings.hyprland
        if (o[key] !== undefined) return o[key]
        if (effective[key] !== undefined) return effective[key]
        return spec(key).def
    }

    function set(key, v) {
        Settings.set("hyprland", key, v)
        applyTimer.restart()
    }

    function reset(key) {
        Settings.reset("hyprland", key)
        applyTimer.restart()
    }

    function resetAll() {
        Settings.resetGroup("hyprland")
        applyTimer.restart()
    }

    // ── Colors: Hyprland uses 0xAARRGGBB, Qt #AARRGGBB (same order) ─────────
    function hex2(x) { return Math.round(x * 255).toString(16).padStart(2, "0") }
    function toHyprColor(c) {
        const q = Qt.color(c)
        return "0x" + hex2(q.a) + hex2(q.r) + hex2(q.g) + hex2(q.b)
    }

    // ── Reading the current values ───────────────────────────────────────────
    function refresh() {
        const main = Files.read(mainConfig)
        root.available = main !== ""
        root.legacyConfig = !root.available && Files.read(configDir + "/hyprland.conf") !== ""
        // a line that loads quickshell.lua and isn't commented out
        root.included = main.split("\n").some(l => !/^\s*--/.test(l) && l.includes("quickshell.lua"))
        if (Compositor.isHyprland && !optionsProc.running) {
            optionsProc.command = ["sh", "-c",
                'for o in "$@"; do printf "%s\\t" "$o"; hyprctl -j getoption "$o" | tr -d "\\n"; echo; done',
                "sh"].concat(schema.map(s => root.pathOf(s)))
            optionsProc.running = true
        }
    }

    // one getoption reply → the value in the settings app's terms
    function fromOption(s, j) {
        switch (s.type) {
        case "bool": return j.bool ?? (j.int !== undefined ? j.int !== 0 : undefined)
        case "int": {
            if (j.int !== undefined) return j.int
            const n = parseInt(String(j.css ?? j.custom ?? "").split(" ")[0])   // gaps: "t r b l"
            return isNaN(n) ? undefined : n
        }
        case "real": return j.float ?? j.int
        case "color": {
            if (j.int !== undefined) return "#" + (j.int >>> 0).toString(16).padStart(8, "0")
            const first = String(j.gradient ?? j.custom ?? "").split(" ")[0]   // "aarrggbb … 45deg"
            return /^[0-9a-f]{8}$/i.test(first) ? "#" + first : undefined
        }
        case "choice":
            if (s.map && j.int !== undefined) return s.options[j.int]
            return s.options.includes(j.str) ? j.str : undefined
        default: return j.str
        }
    }

    Process {
        id: optionsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const eff = {}
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    const s = root.schema.find(x => root.pathOf(x) === line.slice(0, tab))
                    if (!s) continue
                    let j
                    try { j = JSON.parse(line.slice(tab + 1)) } catch (e) { continue }   // "no such option"
                    const v = root.fromOption(s, j)
                    if (v !== undefined) eff[s.key] = v
                }
                root.effective = eff
            }
        }
    }

    // ── Writing the override file ────────────────────────────────────────────
    function luaKey(k) { return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : "[" + Compositor.luaString(k) + "]" }

    function luaValue(s, v) {
        switch (s.type) {
        case "bool":   return v ? "true" : "false"
        case "int":    return String(Math.round(v))
        case "real":   return String(Number(Number(v).toFixed(4)))
        case "color":  return Compositor.luaString(toHyprColor(v))
        case "choice": return s.map ? String(Math.max(0, s.options.indexOf(v))) : Compositor.luaString(v)
        default:       return Compositor.luaString(String(v))
        }
    }

    function render(node, indent) {
        let t = "{\n"
        for (const [k, child] of node) {
            t += indent + "    " + luaKey(k) + " = "
                + (child instanceof Map ? render(child, indent + "    ") : child) + ",\n"
        }
        return t + indent + "}"
    }

    function windowRule(name, title, w, h) {
        return Syntax.fmt("hypr.windowRule", { name: Compositor.luaString(name), title: Compositor.luaString("^" + title + "$"),
                                                width: String(w), height: String(h) }) + "\n\n"
    }

    function generate() {
        const tree = new Map()
        const o = Settings.hyprland
        for (const s of schema) {
            if (o[s.key] === undefined) continue
            const parts = pathOf(s).split(".")
            const leaf = parts.pop()
            let n = tree
            for (const p of parts) {
                if (!n.has(p)) n.set(p, new Map())
                n = n.get(p)
            }
            n.set(leaf, luaValue(s, o[s.key]))
        }

        return "-- Generated by the Quickshell settings app (modules/settings) — edits here\n"
            + "-- get overwritten. Loaded last by hyprland.lua, so these values win over\n"
            + "-- the rest of the config. Change them in the app, or remove the dofile\n"
            + "-- line from hyprland.lua to drop all of them.\n\n"
            + (tree.size > 0 ? Syntax.fmt("hypr.config", { body: render(tree, "") }) + "\n\n" : "")
            + "-- the settings and calendar windows\n"
            + windowRule("quickshell-settings", windowTitle, 980, 680)
            + windowRule("quickshell-calendar", "Quickshell Calendar", 1240, 800)
            + Syntax.fmt("hypr.bind", { keys: Syntax.luaString(Syntax.hyprKeys(["Mod", "S"])),
                                        action: Syntax.fmt("hypr.exec", { cmd: Syntax.luaString("qs ipc call settings toggle") }),
                                        opts: Syntax.lua({ description: "Settings" }) }) + "\n\n"
            + generateBinds()
            + generateAutostart()
            + "-- monitor setup from the Monitors page\n"
            + "pcall(dofile, " + Compositor.luaString(monitorsPath) + ")\n"
    }

    // keybinds from the Keybinds page (Settings.keybinds.binds): own binds,
    // binds from your config moved to other keys, and disabled ones
    function generateBinds() {
        const list = Keybinds.effectiveCustom("hyprland")
        if (list.length === 0) return ""
        let t = "-- keybinds from the Keybinds page\n"
        for (const b of list) {
            const keys = Syntax.luaString(Syntax.hyprKeys(b.keys))
            // unbind first: Hyprland would run both binds of the same keys
            t += Syntax.fmt("hypr.unbind", { keys: keys }) + "\n"
            if (b.kind === "disable") continue
            const action = b.kind === "original" ? b.raw.hypr : Syntax.fmt("hypr.exec", { cmd: Syntax.luaString(b.cmd) })
            const opts = Object.assign({}, b.kind === "original" ? (b.opts ?? {}) : {}, b.name ? { description: b.name } : {})
            t += Syntax.fmt("hypr.bind", { keys: keys, action: action, opts: Syntax.lua(opts) }) + "\n"
        }
        return t + "\n"
    }

    // programs started at login (Settings.autostart.items)
    function generateAutostart() {
        const items = (Settings.autostart.items ?? []).filter(a => a.enabled !== false && a.cmd && (a.on ?? "both") !== "niri")
        if (items.length === 0) return ""
        return "-- started at login (Autostart page)\n"
            + items.map(a => Syntax.fmt("hypr.autostart", { cmd: Syntax.luaString(a.cmd) })).join("\n") + "\n\n"
    }

    // sh -c script: args $1 = text, $2 = target file. Checks the text with
    // `Hyprland --verify-config` (a file with only some settings is a valid
    // config on its own) and only then writes it; errors go to stderr. The
    // file is overwritten in place (so Hyprland's file watch keeps working),
    // then a running Hyprland reloads.
    readonly property string installScript:
        'tmp=$(mktemp --suffix=.lua) || exit 1\n'
        + 'printf "%s" "$1" > "$tmp"\n'
        + 'if out=$(HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 Hyprland --verify-config -c "$tmp" 2>&1); then\n'
        + '  mkdir -p "$(dirname "$2")" && cat "$tmp" > "$2"; rm -f "$tmp"\n'
        + '  [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && hyprctl reload >/dev/null; exit 0\n'
        + 'else\n'
        + '  rm -f "$tmp"\n'
        + '  printf "%s\\n" "$out" | sed "s/\\x1b\\[[0-9;]*m//g" | sed -n "/Config parsing result/,\\$p" | tail -n +2'
        + ' | sed "s|$tmp|$(basename "$2")|g" >&2\n'
        + '  exit 1\n'
        + 'fi'

    function apply() {
        if (!available) return
        if (applyProc.running) { applyTimer.restart(); return }
        const text = generate()
        if (text === Files.read(overridePath)) { root.error = ""; return }
        root.applying = true
        applyProc.command = ["sh", "-c", installScript, "sh", text, overridePath]
        applyProc.running = true
    }

    Timer { id: applyTimer; interval: 500; onTriggered: root.apply() }

    Process {
        id: applyProc
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            root.applying = false
            root.error = code === 0 ? "" : (applyErr.text.trim() || "Hyprland --verify-config failed")
            if (code === 0) { refreshTimer.restart(); if (Compositor.isHyprland) Keybinds.refresh() }
        }
    }

    // Hyprland has the new values a moment after the reload
    Timer { id: refreshTimer; interval: 400; onTriggered: root.refresh() }

    // read the current values and bring the override file up to date at
    // startup (only written if it differs)
    Component.onCompleted: { refresh(); applyTimer.restart() }

    // settings.json edited by hand → regenerate too (writes are skipped when nothing changed)
    Connections {
        target: Settings
        function onHyprlandChanged() { applyTimer.restart() }
        function onAutostartChanged() { applyTimer.restart() }
        function onKeybindsChanged() { applyTimer.restart() }
        function onSyntaxChanged() { applyTimer.restart() }
    }
}
