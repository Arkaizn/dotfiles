pragma Singleton
import Quickshell
import QtQuick
import qs.services

// niri's keybinds, read from the config (config.kdl and everything it
// includes, the settings app's override file too) for the cheatsheet
// (modules/keybinds). Uses NiriSettings' KDL reader.
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
        const found = new Map()            // normalized keys → bind; later ones win, like in niri
        let err = ""
        try {
            collect(NiriSettings.mainConfig, found, 0)
        } catch (e) {
            err = "Couldn't read the niri config: " + e
        }
        const list = fold(Array.from(found.values()).filter(b => b.title !== null))
        root.error = err || (list.length === 0 ? "No binds found in " + NiriSettings.mainConfig : "")
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
        root.binds = rows
    }

    Component.onCompleted: refresh()

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

    // Mod+1 … Mod+9 doing "<action> 1" … "<action> 9" → one row, key "1–9"
    function fold(list) {
        const out = []
        const groups = new Map()
        for (const b of list) {
            const last = b.keys[b.keys.length - 1]
            if (/^[0-9]$/.test(last) && b.args.length === 1 && b.args[0] === last && b.title === "") {
                const id = b.keys.slice(0, -1).join("+").toLowerCase() + "|" + b.action
                if (!groups.has(id)) {
                    const g = { keys: b.keys.slice(0, -1), title: "", action: b.action, args: [], digits: [] }
                    groups.set(id, g)
                    out.push(g)
                }
                groups.get(id).digits.push(Number(last))
            } else {
                out.push(b)
            }
        }
        for (const g of groups.values()) {
            const lo = Math.min(...g.digits), hi = Math.max(...g.digits)
            const r = g.digits.length > 1 ? lo + "–" + hi : String(lo)
            g.keys = g.keys.concat(r)
            g.args = [r]
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
        const cmd = b.args.join(" ")
        if (b.action === "spawn" || b.action === "spawn-sh") {
            const ipc = /qs ipc call (\S+) (\S+)/.exec(cmd)
            if (ipc) return qsNames[ipc[1] + "." + ipc[2]] ?? "Quickshell: " + ipc[1] + " " + ipc[2]
            if (/lock\.sh|loginctl lock|swaylock|hyprlock/.test(cmd)) return "Lock screen"
            if (/wlogout/.test(cmd)) return "Power menu"
            if (/tesseract/.test(cmd)) return "Copy text from a region (OCR)"
            if (/grim/.test(cmd)) return /slurp/.test(cmd) ? "Screenshot of a region" : "Screenshot of the screen"
            if (/wpctl set-volume/.test(cmd)) return /[0-9.]+%?\+/.test(cmd) ? "Volume up" : "Volume down"
            if (/wpctl set-mute/.test(cmd)) return /SOURCE/.test(cmd) ? "Mute microphone" : "Mute"
            if (/brightnessctl/.test(cmd)) return /\+/.test(cmd) ? "Brightness up" : "Brightness down"
            const pc = /playerctl (\S+)/.exec(cmd)
            if (pc) return ({ "play-pause": "Play / pause", "next": "Next track", "previous": "Previous track", "stop": "Stop" })[pc[1]] ?? "Player: " + pc[1]
            // plain app: its name
            const prog = (b.action === "spawn" ? b.args[0] : cmd.trim().split(/\s+/)[0]) ?? ""
            const name = prog.replace(/.*\//, "")
            return b.action === "spawn" || b.args.length === 1 && !/[|;&$]/.test(cmd) && cmd.split(/\s+/).length <= 2
                ? "Open " + name : "Run " + (cmd.length > 40 ? cmd.slice(0, 40) + "…" : cmd)
        }
        if (actionNames[b.action]) return actionNames[b.action]
        return humanize(b.action) + (b.args.length > 0 ? " " + b.args.join(" ") : "")
    }

    function category(b) {
        const a = b.action
        const cmd = b.args.join(" ")
        if (a === "spawn" || a === "spawn-sh") {
            if (/qs ipc call/.test(cmd)) return "Quickshell"
            if (/lock\.sh|loginctl lock|swaylock|hyprlock|wlogout/.test(cmd)) return "Session"
            if (/grim/.test(cmd)) return "Screenshots"
            if (/wpctl|playerctl|brightnessctl|pactl|pamixer/.test(cmd) || b.keys.some(k => k.startsWith("XF86"))) return "Media & brightness"
            return "Apps"
        }
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

    // ── Key caps ─────────────────────────────────────────────────────────────
    readonly property var keyNames: ({
        mod: "Super", super: "Super", win: "Super", ctrl: "Ctrl", control: "Ctrl", shift: "Shift", alt: "Alt",
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
        return ["mod", "super", "win", "ctrl", "control", "shift", "alt", "iso_level3_shift", "iso_level5_shift"].includes(k.toLowerCase())
    }
}
