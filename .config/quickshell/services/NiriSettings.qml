pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// niri side of the settings app.
//
// Changed values (Settings.niri) are written to an override file,
// ~/.config/niri/config/quickshell.kdl, which config.kdl includes last, so it
// wins over the hand-written files without ever touching them. Every write is
// checked with `niri validate` first; niri reloads the file by itself.
//
// Unchanged values are shown as they are in your config: the config files are
// read (following includes, skipping the override file) with a small KDL
// reader that knows just enough to find the values in `schema`.
Singleton {
    id: root

    readonly property string configDir: {
        const custom = Quickshell.env("NIRI_CONFIG") ?? ""
        if (custom !== "") return custom.replace(/\/[^/]*$/, "")
        const xdg = Quickshell.env("XDG_CONFIG_HOME") ?? ""
        return (xdg !== "" ? xdg : Quickshell.env("HOME") + "/.config") + "/niri"
    }
    readonly property string mainConfig: {
        const custom = Quickshell.env("NIRI_CONFIG") ?? ""
        return custom !== "" ? custom : configDir + "/config.kdl"
    }
    readonly property string overridePath: configDir + "/config/quickshell.kdl"
    readonly property string includeLine: 'include "./config/quickshell.kdl"'

    // title the settings window uses; the override file makes niri float it
    readonly property string windowTitle: "Quickshell Settings"

    property var effective: ({})     // key → value from your config files
    property bool included: false    // config.kdl includes the override file
    property string error: ""        // last `niri validate` complaint
    property bool applying: false

    // ── What can be changed ──────────────────────────────────────────────────
    //   path: where it lives in the config; "@enabled" = the on/off of a section
    //   def:  niri's own default, used when your config doesn't set it
    readonly property var schema: [
        { key: "gaps", path: "layout/gaps", type: "int", def: 16, min: 0, max: 64,
          label: "Gaps", desc: "Space around windows" },
        { key: "centerColumn", path: "layout/center-focused-column", type: "choice", def: "never",
          options: ["never", "on-overflow", "always"],
          label: "Center focused column", desc: "When the focused column is moved to the middle" },
        { key: "columnWidth", path: "layout/default-column-width/proportion", type: "real", def: 0.5,
          min: 0.1, max: 1, step: 0.05, label: "Default column width", desc: "Width of new windows, as a share of the screen" },
        { key: "cornerRadius", path: "window-rule/geometry-corner-radius", type: "int", def: 0, min: 0, max: 40,
          label: "Window corner radius", desc: "Rounded corners of every window" },
        { key: "preferNoCsd", path: "prefer-no-csd", type: "bool", def: false,
          label: "Prefer no client decorations", desc: "Ask apps to drop their own title bars and shadows" },

        { key: "ringOn", path: "layout/focus-ring/@enabled", type: "bool", def: true,
          label: "Focus ring", desc: "Ring around the focused window" },
        { key: "ringWidth", path: "layout/focus-ring/width", type: "int", def: 4, min: 0, max: 16, label: "Width" },
        { key: "ringActive", path: "layout/focus-ring/active-color", type: "color", def: "#7fc8ff", label: "Active color" },
        { key: "ringInactive", path: "layout/focus-ring/inactive-color", type: "color", def: "#505050",
          label: "Inactive color", desc: "On the focused window of other monitors" },

        { key: "borderOn", path: "layout/border/@enabled", type: "bool", def: false,
          label: "Border", desc: "Border around every window" },
        { key: "borderWidth", path: "layout/border/width", type: "int", def: 4, min: 0, max: 16, label: "Width" },
        { key: "borderInactive", path: "layout/border/inactive-color", type: "color", def: "#505050", label: "Inactive color" },
        { key: "borderUrgent", path: "layout/border/urgent-color", type: "color", def: "#9b0000", label: "Urgent color" },

        { key: "shadowOn", path: "layout/shadow/@enabled", type: "bool", def: false,
          label: "Shadows", desc: "Drop shadow under windows" },
        { key: "shadowSoftness", path: "layout/shadow/softness", type: "int", def: 30, min: 0, max: 100, label: "Softness" },
        { key: "shadowSpread", path: "layout/shadow/spread", type: "int", def: 5, min: 0, max: 50, label: "Spread" },
        { key: "shadowColor", path: "layout/shadow/color", type: "color", def: "#70000000", label: "Color" },

        { key: "animationsOn", path: "animations/@enabled", type: "bool", def: true,
          label: "Animations", desc: "Window and workspace animations" },
        { key: "slowdown", path: "animations/slowdown", type: "real", def: 1.0, min: 0.1, max: 4, step: 0.1,
          label: "Slowdown", desc: "Above 1 is slower, below 1 is faster" },
        { key: "blurPasses", path: "blur/passes", type: "int", def: 2, min: 1, max: 8,
          label: "Blur passes", desc: "More passes = smoother blur" },
        { key: "blurOffset", path: "blur/offset", type: "real", def: 3, min: 0, max: 20, step: 0.5,
          label: "Blur offset", desc: "How far the blur spreads per pass" },

        { key: "kbLayout", path: "input/keyboard/xkb/layout", type: "string", def: "us",
          label: "Keyboard layout", desc: "XKB layout(s), e.g. \"ch\" or \"us,de\"" },
        { key: "numlock", path: "input/keyboard/numlock", type: "bool", def: false,
          label: "Numlock on startup" },
        { key: "touchpadAccel", path: "input/touchpad/accel-speed", type: "real", def: 0, min: -1, max: 1, step: 0.05,
          label: "Touchpad speed" },
        { key: "mouseAccel", path: "input/mouse/accel-speed", type: "real", def: 0, min: -1, max: 1, step: 0.05,
          label: "Mouse speed" },
        { key: "cursorSize", path: "cursor/xcursor-size", type: "int", def: 24, min: 8, max: 96,
          label: "Cursor size" }
    ]

    function spec(key) { return schema.find(s => s.key === key) }

    function value(key) {
        const o = Settings.niri
        if (o[key] !== undefined) return o[key]
        if (effective[key] !== undefined) return effective[key]
        return spec(key).def
    }

    function set(key, v) {
        Settings.set("niri", key, v)
        applyTimer.restart()
    }

    function reset(key) {
        Settings.reset("niri", key)
        applyTimer.restart()
    }

    function resetAll() {
        Settings.resetGroup("niri")
        applyTimer.restart()
    }

    // ── Colors: niri writes #rrggbbaa, Qt reads #aarrggbb ───────────────────
    function hex2(x) { return Math.round(x * 255).toString(16).padStart(2, "0") }
    function toNiriColor(c) {
        const q = Qt.color(c)
        return "#" + hex2(q.r) + hex2(q.g) + hex2(q.b) + (q.a < 1 ? hex2(q.a) : "")
    }
    function fromNiriColor(s) {
        const m = /^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(s)
        if (!m) return Qt.color(s)   // named colors
        let h = m[1]
        if (h.length <= 4) h = h.split("").map(ch => ch + ch).join("")
        return h.length === 8 ? Qt.color("#" + h.slice(6) + h.slice(0, 6)) : Qt.color("#" + h)
    }

    // ── Reading your config ──────────────────────────────────────────────────
    FileView { id: reader; blockLoading: true; printErrors: false }

    function readFile(p) {
        reader.path = ""
        reader.path = p
        return reader.text() ?? ""
    }

    function expand(p, baseDir) {
        if (p.startsWith("~/")) return Quickshell.env("HOME") + p.slice(1)
        if (p.startsWith("/")) return p
        return baseDir + "/" + p.replace(/^\.\//, "")
    }

    // string body starting after the opening quote; returns [value, index after closing quote]
    function readString(src, i, hashes) {
        if (hashes >= 0) {   // raw string r#"..."#
            const close = '"' + "#".repeat(hashes)
            const k = src.indexOf(close, i)
            return k < 0 ? [src.slice(i), src.length] : [src.slice(i, k), k + close.length]
        }
        let s = ""
        while (i < src.length && src[i] !== '"') {
            if (src[i] === "\\" && i + 1 < src.length) {
                const e = src[i + 1]
                s += e === "n" ? "\n" : e === "t" ? "\t" : e
                i += 2
            } else {
                s += src[i++]
            }
        }
        return [s, i + 1]
    }

    function tokenize(src) {
        const toks = []
        let i = 0
        const n = src.length
        while (i < n) {
            const c = src[i]
            if (c === "\n" || c === ";") { toks.push({ t: "end" }); i++; continue }
            if (c === " " || c === "\t" || c === "\r") { i++; continue }
            if (src.startsWith("//", i)) { while (i < n && src[i] !== "\n") i++; continue }
            if (src.startsWith("/*", i)) { const j = src.indexOf("*/", i + 2); i = j < 0 ? n : j + 2; continue }
            if (src.startsWith("/-", i)) { toks.push({ t: "slashdash" }); i += 2; continue }
            if (c === "\\") { while (i < n && src[i] !== "\n") i++; i++; continue }   // line continuation
            if (c === "{" || c === "}") { toks.push({ t: c }); i++; continue }
            if (c === '"') { const r = readString(src, i + 1, -1); toks.push({ t: "str", v: r[0] }); i = r[1]; continue }
            const raw = /^r(#*)"/.exec(src.slice(i, i + 10))
            if (raw) { const r = readString(src, i + raw[0].length, raw[1].length); toks.push({ t: "str", v: r[0] }); i = r[1]; continue }

            let w = ""
            while (i < n && !/[\s;{}"]/.test(src[i])) w += src[i++]
            const eq = w.indexOf("=")
            if (eq >= 0) {
                // property like key=value / key="value" / key=r#"value"#: skip it
                const val = w.slice(eq + 1)
                if (i < n && src[i] === '"' && (val === "" || /^r#*$/.test(val))) {
                    const r = readString(src, i + 1, val === "" ? -1 : val.length - 1)
                    i = r[1]
                }
                toks.push({ t: "prop" })
                continue
            }
            toks.push({ t: "word", v: w })
        }
        toks.push({ t: "end" })
        return toks
    }

    // fills `out` with "path/to/node" → { args, order }; later nodes win
    function parseInto(file, out, state, depth) {
        if (depth > 8) return
        const src = readFile(file)
        const baseDir = file.replace(/\/[^/]*$/, "")
        const stack = []
        let cur = null
        let skipNext = false

        function finish() {
            if (!cur) return
            const node = cur
            cur = null
            if (node.skip || stack.some(s => s.skip)) return
            const path = stack.map(s => s.name).concat(node.name).join("/")
            if (path === "include") {
                const target = node.args.length > 0 ? expand(node.args[node.args.length - 1], baseDir) : ""
                if (target !== "" && target !== root.overridePath) parseInto(target, out, state, depth + 1)
                return
            }
            out[path] = { args: node.args, order: state.order++ }
        }

        for (const tok of tokenize(src)) {
            switch (tok.t) {
            case "slashdash": skipNext = true; break
            case "word":
            case "str":
                if (!cur) { cur = { name: tok.v, args: [], skip: skipNext }; skipNext = false }
                else cur.args.push(tok.v)
                break
            case "prop": break
            case "end": finish(); break
            case "{": {
                const name = cur ? cur.name : ""
                const skip = cur ? cur.skip : skipNext
                finish()
                skipNext = false
                stack.push({ name: name, skip: skip })
                break
            }
            case "}": finish(); stack.pop(); break
            }
        }
    }

    function refresh() {
        const out = {}
        parseInto(mainConfig, out, { order: 0 }, 0)

        const eff = {}
        for (const s of schema) {
            if (s.path.endsWith("/@enabled")) {
                const sec = s.path.slice(0, -"/@enabled".length)
                const on = out[sec + "/on"], off = out[sec + "/off"]
                if (on || off) eff[s.key] = (on ? on.order : -1) > (off ? off.order : -1)
                continue
            }
            const n = out[s.path]
            if (!n) continue
            const a = n.args[0]
            if (s.type === "bool") eff[s.key] = a === undefined || a === "true"
            else if (a === undefined) continue
            else if (s.type === "int" || s.type === "real") { const f = parseFloat(a); if (!isNaN(f)) eff[s.key] = f }
            else if (s.type === "color") eff[s.key] = fromNiriColor(a).toString()
            else eff[s.key] = a
        }
        root.effective = eff
        root.included = readFile(mainConfig).split("\n").some(l => l.trim() === root.includeLine)
    }

    // ── Writing the override file ────────────────────────────────────────────
    function line(s, leaf, v) {
        if (leaf === "@enabled") return v ? "on" : "off"
        switch (s.type) {
        case "bool":   return v ? leaf : leaf + " false"
        case "int":    return leaf + " " + Math.round(v)
        case "real":   return leaf + " " + Number(Number(v).toFixed(3))
        case "color":  return leaf + ' "' + toNiriColor(v) + '"'
        default:       return leaf + " " + JSON.stringify(String(v))
        }
    }

    function render(node, indent) {
        let t = ""
        for (const l of node.lines) t += indent + l + "\n"
        for (const [name, child] of node.children) {
            t += indent + name + " {\n" + render(child, indent + "    ") + indent + "}\n"
        }
        return t
    }

    function generate() {
        const tree = { children: new Map(), lines: [] }
        const o = Settings.niri
        for (const s of schema) {
            if (o[s.key] === undefined) continue
            const parts = s.path.split("/")
            const leaf = parts.pop()
            let n = tree
            for (const p of parts) {
                if (!n.children.has(p)) n.children.set(p, { children: new Map(), lines: [] })
                n = n.children.get(p)
            }
            n.lines.push(line(s, leaf, o[s.key]))
        }

        return "// Generated by the Quickshell settings app (modules/settings) — edits here\n"
            + "// get overwritten. Included last by config.kdl, so these values win over\n"
            + "// the rest of the config. Change them in the app, or remove the include\n"
            + "// line from config.kdl to drop all of them.\n\n"
            + render(tree, "")
            + "\n// the settings window itself\n"
            + "window-rule {\n"
            + "    match title=\"^" + windowTitle + "$\"\n"
            + "    open-floating true\n"
            + "    default-column-width { fixed 980; }\n"
            + "    default-window-height { fixed 680; }\n"
            + "    geometry-corner-radius " + Math.round(Properties.panelRadius) + "\n"
            + "    clip-to-geometry true\n"
            + "    draw-border-with-background false\n"
            + "    background-effect { blur true; }\n"
            + "}\n\n"
            + "binds {\n"
            + "    Mod+S hotkey-overlay-title=\"Settings\" { spawn-sh \"qs ipc call settings toggle\"; }\n"
            + "}\n"
    }

    function apply() {
        if (applyProc.running) { applyTimer.restart(); return }
        const text = generate()
        if (text === readFile(overridePath)) { root.error = ""; return }
        root.applying = true
        applyProc.command = ["sh", "-c",
            'tmp=$(mktemp "$2.XXXXXX") || exit 1\n'
            + 'printf "%s" "$1" > "$tmp"\n'
            + 'if out=$(niri validate -c "$tmp" 2>&1); then mv "$tmp" "$2"\n'
            + 'else rm -f "$tmp"; printf "%s\\n" "$out" | sed "s/\\x1b\\[[0-9;]*m//g" | grep -vE " (DEBUG|INFO) " >&2; exit 1; fi',
            "sh", text, overridePath]
        applyProc.running = true
    }

    Timer { id: applyTimer; interval: 500; onTriggered: root.apply() }

    Process {
        id: applyProc
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            root.applying = false
            root.error = code === 0 ? "" : (applyErr.text.trim() || "niri validate failed")
        }
    }

    // the settings window's corners follow panelRadius
    Connections {
        target: Properties
        function onPanelRadiusChanged() { applyTimer.restart() }
    }
}
