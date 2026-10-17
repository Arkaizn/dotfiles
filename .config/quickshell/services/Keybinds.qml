pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// The compositor's keybinds for the cheatsheet (modules/keybinds).
//   niri:     read from the config (config.kdl and everything it includes, the
//             settings app's override file too) with NiriSettings' KDL reader
//   Hyprland: scripts/hypr-binds.lua runs hyprland.lua against a stand-in
//             `hl` that records every hl.bind (`hyprctl binds` can't say what
//             a Lua bind does), so loops and variables come out right
//
// Each row: { combos: [["Mod", "Shift", "Left"], …], desc, category }
// The title comes from hotkey-overlay-title if the bind has one (=null hides
// it, like in niri's own overlay), otherwise it's made from the action.
// Binds that only differ by a digit (Mod+1 … Mod+9 → workspace 1 … 9) are
// folded into one row with the key "1–9", and binds that do the same thing
// (Mod+U and Mod+Page_Down) share a row with both combos.
Singleton {
    id: root

    property var binds: []
    property string error: ""

    // the "Most important" card of the cheatsheet: the first bind matching
    // each of these (in this order), at most `importantMax`
    readonly property int importantMax: 10
    readonly property var importantPatterns: [
        /^App launcher$/, /^Open (kitty|alacritty|foot|wezterm|ghostty|konsole|gnome-terminal|terminal)/i,
        /^Close window$/, /^Fullscreen window$/, /^(Maximize column|Maximize window)$/, /^Float \/ tile window$/,
        /^Overview$/, /^Focus workspace [0-9]+–[0-9]+$/, /^Move (column|window) to workspace [0-9]+–[0-9]+$/,
        /^Clipboard history$/, /^Screenshot of a region$/, /^Settings$/, /^Wallpaper picker$/,
        /^Lock screen$/, /^(Power menu|Logout screen|Quit niri|Quit Hyprland)$/
    ]
    readonly property var important: {
        const out = []
        for (const re of importantPatterns) {
            const b = binds.find(x => re.test(x.desc) && !out.includes(x))
            if (b) out.push(b)
            if (out.length >= importantMax) break
        }
        return out
    }

    // shown in this order, with these icons
    readonly property var categories: [
        { name: "Apps", icon: "󰀻" },
        { name: "Quickshell", icon: "󰕮" },
        { name: "Focus", icon: "󰆾" },
        { name: "Move", icon: "󰁁" },
        { name: "Window size & layout", icon: "󰖲" },
        { name: "Workspaces", icon: "󰖯" },
        { name: "Monitors", icon: "󰍹" },
        { name: "Screenshots", icon: "󰹑" },
        { name: "Media & brightness", icon: "󰝚" },
        { name: "Session", icon: "󰐥" },
        { name: "Other", icon: "󰌌" }
    ]

    function refresh() {
        if (Compositor.isHyprland) {
            if (!hyprProc.running) hyprProc.running = true
            return
        }
        const found = new Map()            // normalized keys → bind; later ones win, like in niri
        let err = ""
        try {
            collect(NiriSettings.mainConfig, found, 0)
        } catch (e) {
            err = "Couldn't read the niri config: " + e
        }
        const list = fold(Array.from(found.values()).filter(b => b.title !== null))
        root.error = err || (list.length === 0 ? "No binds found in " + NiriSettings.mainConfig : "")
        root.binds = rows(list)
    }

    // binds → rows; binds that do the same thing share a row
    function rows(list) {
        const rows = []
        const byDesc = new Map()
        for (const b of list) {
            const desc = describe(b), cat = category(b)
            const id = cat + "|" + desc
            if (byDesc.has(id)) { byDesc.get(id).combos.push(b.keys); continue }
            const row = { combos: [b.keys], desc: desc, category: cat }
            byDesc.set(id, row)
            rows.push(row)
        }
        return rows
    }

    Component.onCompleted: refresh()

    // ── Hyprland ─────────────────────────────────────────────────────────────
    Process {
        id: hyprProc
        command: ["lua", Quickshell.shellDir + "/scripts/hypr-binds.lua", HyprSettings.mainConfig]
        stdout: StdioCollector { id: hyprOut }
        stderr: StdioCollector { id: hyprErr }
        onExited: code => {
            let raw = []
            try { raw = JSON.parse(hyprOut.text) } catch (e) {}
            const list = fold(raw.map(b => ({
                keys: b.keys.split("+").map(k => k.trim()).filter(k => k !== ""),
                title: b.description ?? "",
                action: b.dsp,
                args: b.args ?? [],
                submap: b.submap ?? "",
                hypr: true
            })))
            root.binds = rows(list)
            // a config that fails halfway still gives the binds before the error
            root.error = list.length > 0 ? ""
                : code === 127 ? "lua isn't installed (needed to read Hyprland's Lua config)"
                : "Couldn't read the binds from " + HyprSettings.mainConfig
                  + (hyprErr.text.trim() !== "" ? ": " + hyprErr.text.trim() : "")
        }
    }

    // ── Reading ──────────────────────────────────────────────────────────────
    // tokens → nodes { name, args, props, children, skip }
    function tree(toks) {
        const top = { children: [] }
        const stack = [top]
        let cur = null
        let skipNext = false
        const node = name => ({ name: name, args: [], props: {}, children: [], skip: skipNext })
        function finish() { if (cur) { stack[stack.length - 1].children.push(cur); cur = null } }
        for (const tok of toks) {
            switch (tok.t) {
            case "slashdash": skipNext = true; break
            case "word":
            case "str":
                if (!cur) { cur = node(tok.v); skipNext = false }
                else cur.args.push(tok.v)
                break
            case "prop":
                if (cur) cur.props[tok.k] = tok.quoted || tok.v !== "null" ? tok.v : null
                break
            case "end": finish(); break
            case "{": {
                if (!cur) cur = node("")
                skipNext = false
                const n = cur
                finish()
                stack.push(n)
                break
            }
            case "}": finish(); if (stack.length > 1) stack.pop(); break
            }
        }
        finish()
        return top.children
    }

    function collect(file, found, depth) {
        if (depth > 8) return
        const baseDir = file.replace(/\/[^/]*$/, "")
        for (const n of tree(NiriSettings.tokenize(NiriSettings.readFile(file)))) {
            if (n.skip) continue
            if (n.name === "include" && n.args.length > 0) {
                collect(NiriSettings.expand(n.args[n.args.length - 1], baseDir), found, depth + 1)
            } else if (n.name === "binds") {
                for (const b of n.children) {
                    if (b.skip || b.name === "") continue
                    const act = b.children.find(c => !c.skip)
                    if (!act) continue
                    const title = b.props["hotkey-overlay-title"]
                    found.delete(b.name.toLowerCase())    // re-insert: an override moves to where it's defined last
                    found.set(b.name.toLowerCase(), {
                        keys: b.name.split("+"),
                        title: title === undefined ? "" : title,
                        action: act.name,
                        args: act.args
                    })
                }
            }
        }
    }

    // the number a bind passes on: niri `focus-workspace 3` → 3,
    // Hyprland hl.dsp.focus({ workspace = 3 }) → 3
    function numberArg(b) {
        if (b.hypr) return typeof b.args[0]?.workspace === "number" && b.args.length === 1 ? b.args[0].workspace : null
        return b.args.length === 1 && /^[0-9]+$/.test(b.args[0]) ? Number(b.args[0]) : null
    }

    // Mod+1 … Mod+9 doing "<action> 1" … "<action> 9" → one row, key "1–9"
    // (Hyprland's usual loop also binds 0 → workspace 10: key "0–9", workspace "1–10")
    function fold(list) {
        const out = []
        const groups = new Map()
        for (const b of list) {
            const last = b.keys[b.keys.length - 1]
            const n = numberArg(b)
            const digit = /^[0-9]$/.test(last) ? Number(last) : -1
            if (digit >= 0 && n !== null && (n === digit || (digit === 0 && n === 10)) && b.title === "") {
                const rest = b.hypr ? Object.assign({}, b.args[0], { workspace: null }) : null
                const id = b.keys.slice(0, -1).join("+").toLowerCase() + "|" + b.action + "|" + JSON.stringify(rest) + "|" + (b.submap ?? "")
                if (!groups.has(id)) {
                    const g = { keys: b.keys.slice(0, -1), title: "", action: b.action, args: [], hypr: b.hypr, submap: b.submap,
                                rest: rest, digits: [], numbers: [] }
                    groups.set(id, g)
                    out.push(g)
                }
                groups.get(id).digits.push(digit)
                groups.get(id).numbers.push(n)
            } else {
                out.push(b)
            }
        }
        const range = xs => {
            const lo = Math.min(...xs), hi = Math.max(...xs)
            return xs.length > 1 ? lo + "–" + hi : String(lo)
        }
        for (const g of groups.values()) {
            g.keys = g.keys.concat(range(g.digits))
            const r = range(g.numbers)
            g.args = g.hypr ? [Object.assign({}, g.rest, { workspace: r })] : [r]
        }
        return out
    }

    // ── Describing ───────────────────────────────────────────────────────────
    readonly property var qsNames: ({
        "Launcher.toggleAppSearch": "App launcher",
        "Launcher.toggleClipboard": "Clipboard history",
        "Launcher.toggleWallpapers": "Wallpaper picker",
        "Launcher.toggleStartMenu": "Start menu",
        "wallpapers.toggle": "Wallpaper picker",
        "settings.toggle": "Settings",
        "settings.open": "Settings",
        "keybinds.toggle": "Keybind cheatsheet",
        "Launcher.toggleKeybinds": "Keybind cheatsheet",
        "dashboard.toggle": "Dashboard",
        "controlCenter.toggle": "Control center",
        "testing.toggle": "Testing panel"
    })

    readonly property var actionNames: ({
        "show-hotkey-overlay": "niri's hotkey overlay",
        "toggle-overview": "Overview",
        "close-window": "Close window",
        "quit": "Quit niri",
        "power-off-monitors": "Turn off monitors",
        "toggle-keyboard-shortcuts-inhibit": "Let the app take all shortcuts",
        "consume-or-expel-window-left": "Window into / out of column, left",
        "consume-or-expel-window-right": "Window into / out of column, right",
        "consume-window-into-column": "Pull next window into column",
        "expel-window-from-column": "Push bottom window out of column",
        "switch-preset-column-width": "Cycle column width",
        "switch-preset-column-width-back": "Cycle column width back",
        "switch-preset-window-height": "Cycle window height",
        "reset-window-height": "Reset window height",
        "maximize-window-to-edges": "Maximize to screen edges",
        "expand-column-to-available-width": "Fill the free width",
        "center-visible-columns": "Center visible columns",
        "toggle-window-floating": "Float / tile window",
        "switch-focus-between-floating-and-tiling": "Focus floating ↔ tiling",
        "toggle-column-tabbed-display": "Tabbed column"
    })

    function humanize(s) {
        const t = s.replace(/-/g, " ")
        return t.charAt(0).toUpperCase() + t.slice(1)
    }

    function describe(b) {
        if (b.title) return b.title
        if (b.hypr && b.action === "submap" && b.args[0] === "reset" && b.submap) return "Leave " + b.submap + " mode"
        if (b.hypr) return describeHypr(b) + (b.submap ? " (" + b.submap + " mode)" : "")
        if (b.action === "spawn" || b.action === "spawn-sh") return describeCommand(b.args.join(" "), b.action === "spawn" ? b.args : null)
        if (actionNames[b.action]) return actionNames[b.action]
        return humanize(b.action) + (b.args.length > 0 ? " " + b.args.join(" ") : "")
    }

    // what a command does; `argv` when it runs a program directly (niri spawn)
    function describeCommand(cmd, argv) {
        const ipc = /qs ipc(?: -[pc] \S+)? call (\S+) (\S+)/.exec(cmd)
        if (ipc) return qsNames[ipc[1] + "." + ipc[2]] ?? "Quickshell: " + ipc[1] + " " + ipc[2]
        if (/lock\.sh|loginctl lock|swaylock|hyprlock/.test(cmd)) return "Lock screen"
        if (/wlogout/.test(cmd)) return "Power menu"
        if (/grim|hyprshot|quicksnip|flameshot|grimblast/.test(cmd)) {
            if (/tesseract|quicksnip/.test(cmd)) return "Copy text from a region (OCR)"
            if (/-m window|active/.test(cmd)) return "Screenshot of the window"
            return /slurp|region/.test(cmd) ? "Screenshot of a region" : "Screenshot of the screen"
        }
        if (/wpctl set-volume/.test(cmd)) return /[0-9.]+%?\+/.test(cmd) ? "Volume up" : "Volume down"
        if (/wpctl set-mute/.test(cmd)) return /SOURCE/.test(cmd) ? "Mute microphone" : "Mute"
        if (/brightnessctl/.test(cmd)) return /\+/.test(cmd) ? "Brightness up" : "Brightness down"
        const pc = /playerctl (\S+)/.exec(cmd)
        if (pc) return ({ "play-pause": "Play / pause", "next": "Next track", "previous": "Previous track", "stop": "Stop" })[pc[1]] ?? "Player: " + pc[1]
        const words = argv ?? cmd.trim().split(/\s+/)
        const base = w => (w ?? "").replace(/.*\//, "")
        // a script: its name ("bash ~/x/select_wallpaper.sh" → "Run select_wallpaper")
        if (/^(ba|z|da)?sh$|^python3?$/.test(base(words[0])) && /\.(sh|py)$/.test(words[1] ?? ""))
            return "Run " + base(words[1]).replace(/\.(sh|py)$/, "")
        // an app, maybe with options: its name; anything else: the command
        if (argv || !/[|;&$]/.test(cmd) && (words.length === 1 || words[1].startsWith("-")))
            return "Open " + base(words[0])
        return "Run " + (cmd.length > 40 ? cmd.slice(0, 40) + "…" : cmd)
    }

    // Hyprland: hl.dsp.<action>(args)
    function describeHypr(b) {
        const a = b.args[0]
        const o = a !== null && typeof a === "object" ? a : {}
        const dir = d => ({ l: "left", r: "right", u: "up", d: "down", t: "up", b: "down" })[d] ?? d
        const ws = w => {
            const t = String(w)
            if (/^[0-9–]+$/.test(t)) return "workspace " + t
            if (/^[emr]\+1$/.test(t)) return "next workspace"
            if (/^[emr]-1$/.test(t)) return "previous workspace"
            if (t === "previous") return "previous workspace"
            if (t.startsWith("empty")) return "next empty workspace"
            if (t.startsWith("name:")) return "workspace \"" + t.slice(5) + "\""
            if (t.startsWith("special")) return "scratchpad" + (t.includes(":") ? " " + t.split(":")[1] : "")
            return "workspace " + t
        }
        switch (b.action) {
        case "exec_cmd":
        case "exec_raw": return describeCommand(String(a ?? ""), null)
        case "window.close": return "Close window"
        case "window.kill": return "Kill window"
        case "window.float": return "Float / tile window"
        case "window.fullscreen": return o.mode === 1 ? "Maximize window" : "Fullscreen window"
        case "window.pseudo": return "Pseudotile window"
        case "window.pin": return "Pin window"
        case "window.center": return "Center window"
        case "window.drag": return "Move window (drag)"
        case "window.resize": return o.direction || o.x !== undefined ? "Resize window" : "Resize window (drag)"
        case "window.cycle_next": return "Cycle windows"
        case "window.swap": return "Swap window" + (o.direction ? " " + dir(o.direction) : "")
        case "window.move":
            if (o.workspace !== undefined) return "Move window to " + ws(o.workspace) + (o.silent || o.follow === false ? " (stay)" : "")
            if (o.direction) return "Move window " + dir(o.direction)
            if (o.monitor) return "Move window to monitor " + o.monitor
            return "Move window"
        case "focus":
            if (o.workspace !== undefined) return "Focus " + ws(o.workspace)
            if (o.direction) return "Focus " + dir(o.direction)
            if (o.monitor) return "Focus monitor " + o.monitor
            return "Focus window"
        case "layout": return a === "togglesplit" ? "Toggle split" : "Layout: " + a
        case "submap": return a === "reset" ? "Leave the mode" : "Enter " + a + " mode"
        case "exit": return "Quit Hyprland"
        case "dpms": return "Turn monitors on / off"
        case "workspace.toggle_special": return "Toggle " + ws("special" + (a ? ":" + (o.name ?? a) : ""))
        case "workspace.move": return "Move workspace to monitor" + (o.monitor ? " " + o.monitor : "")
        case "group.toggle": return "Group windows"
        case "group.next": return "Next window in group"
        case "group.prev": return "Previous window in group"
        case "lua": return "Lua function"
        default: return humanize(b.action.replace(/[._]/g, " "))
        }
    }

    function category(b) {
        const a = b.action
        if (b.hypr) return categoryHypr(b)
        const cmd = b.args.join(" ")
        if (a === "spawn" || a === "spawn-sh") return commandCategory(cmd, b.keys)
        if (/^screenshot/.test(a)) return "Screenshots"
        if (["quit", "power-off-monitors", "show-hotkey-overlay", "toggle-overview",
             "toggle-keyboard-shortcuts-inhibit"].includes(a)) return "Session"
        if (/monitor/.test(a)) return "Monitors"
        if (/workspace/.test(a)) return "Workspaces"
        if (/^focus-/.test(a)) return "Focus"
        if (/^move-/.test(a)) return "Move"
        if (/window|column|maximize|fullscreen|floating|width|height/.test(a)) return "Window size & layout"
        return "Other"
    }

    function categoryHypr(b) {
        const a = b.action
        const o = b.args[0] !== null && typeof b.args[0] === "object" ? b.args[0] : {}
        if (a === "exec_cmd" || a === "exec_raw") return commandCategory(String(b.args[0] ?? ""), b.keys)
        if (a === "focus" || a === "window.move") {
            if (o.workspace !== undefined) return "Workspaces"
            if (o.monitor !== undefined) return "Monitors"
            return a === "focus" ? "Focus" : "Move"
        }
        if (a === "window.swap" || a === "window.drag") return "Move"
        if (a.startsWith("workspace.")) return "Workspaces"
        if (["exit", "dpms", "submap"].includes(a)) return "Session"
        if (a.startsWith("window.") || a.startsWith("group.") || a === "layout") return "Window size & layout"
        return "Other"
    }

    function commandCategory(cmd, keys) {
        if (/qs ipc/.test(cmd)) return "Quickshell"
        if (/lock\.sh|loginctl lock|swaylock|hyprlock|wlogout/.test(cmd)) return "Session"
        if (/grim|hyprshot|quicksnip|flameshot|grimblast/.test(cmd)) return "Screenshots"
        if (/wpctl|playerctl|brightnessctl|pactl|pamixer/.test(cmd) || keys.some(k => k.startsWith("XF86"))) return "Media & brightness"
        return "Apps"
    }

    // ── Key caps ─────────────────────────────────────────────────────────────
    readonly property var keyNames: ({
        mod: "Super", super: "Super", win: "Super", mod4: "Super", ctrl: "Ctrl", control: "Ctrl", shift: "Shift", alt: "Alt",
        iso_level3_shift: "AltGr", iso_level5_shift: "Mod5",
        left: "←", right: "→", up: "↑", down: "↓",
        return: "Enter", enter: "Enter", kp_enter: "Enter", tab: "Tab", escape: "Esc", space: "Space",
        backspace: "⌫", delete: "Del", insert: "Ins", home: "Home", end: "End",
        page_up: "PgUp", page_down: "PgDn", prior: "PgUp", next: "PgDn", print: "Print",
        bracketleft: "[", bracketright: "]", comma: ",", period: ".", minus: "-", equal: "=",
        slash: "/", backslash: "\\", semicolon: ";", apostrophe: "'", grave: "`",
        wheelscrollup: "Wheel ↑", wheelscrolldown: "Wheel ↓", wheelscrollleft: "Wheel ←", wheelscrollright: "Wheel →",
        touchpadscrollup: "Touchpad ↑", touchpadscrolldown: "Touchpad ↓",
        touchpadscrollleft: "Touchpad ←", touchpadscrollright: "Touchpad →",
        mouse_up: "Wheel ↑", mouse_down: "Wheel ↓", mouse_left: "Wheel ←", mouse_right: "Wheel →",
        "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
        section: "§",
        xf86audioraisevolume: "Vol +", xf86audiolowervolume: "Vol −", xf86audiomute: "Mute",
        xf86audiomicmute: "Mic mute", xf86audioplay: "Play", xf86audiopause: "Pause", xf86audiostop: "Stop",
        xf86audioprev: "Prev", xf86audionext: "Next",
        xf86monbrightnessup: "Bright +", xf86monbrightnessdown: "Bright −"
    })

    function keyLabel(k) {
        const n = keyNames[k.toLowerCase()]
        if (n) return n
        if (k.startsWith("XF86")) return k.slice(4)
        return k.length === 1 ? k.toUpperCase() : k
    }

    function isModifier(k) {
        return ["mod", "super", "win", "mod4", "ctrl", "control", "shift", "alt", "iso_level3_shift", "iso_level5_shift"].includes(k.toLowerCase())
    }
}
