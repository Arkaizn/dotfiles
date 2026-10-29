pragma Singleton
import Quickshell
import QtQuick
import qs.services

// The config syntax the shell writes for niri / Hyprland, all editable
// (settings app → Syntax). If a compositor update renames or reshapes
// something, fix it there instead of in the code; every write is still
// validated (`niri validate` / `Hyprland --verify-config`), so a broken
// template is rejected and shown, never written.
//
// Two kinds of placeholders in templates:
//   {@word}   a name the compositor uses (keyword, function, …) — the
//             "Words" list, e.g. {@autostart} = spawn-sh-at-startup
//   {value}   what the shell fills in, e.g. {cmd} = "cliphist wipe"
//             (strings come already quoted for the target language)
// Example: niri renames `spawn-sh-at-startup "x"` to
// `spawn-shell-at-startup="x"` → template niri.autostart = "{@autostart}={cmd}"
// and word autostart = spawn-shell-at-startup.
//
//   fmt(name, { cmd: "\"kitty\"" })   fills a template
//   word("niri", "on")                one word
//   path(store, key, def)             option path of a setting
Singleton {
    id: root

    // ── Words (names the compositor uses) ───────────────────────────────────
    readonly property var wordDefaults: ({
        niri: {
            mod: "Mod", on: "on", off: "off", true: "true", false: "false", null: "null",
            binds: "binds", hotkeyOverlayTitle: "hotkey-overlay-title", spawn: "spawn", spawnSh: "spawn-sh",
            autostart: "spawn-sh-at-startup", include: "include",
            windowRule: "window-rule", match: "match", title: "title", openFloating: "open-floating", openMaximized: "open-maximized",
            defaultColumnWidth: "default-column-width", defaultWindowHeight: "default-window-height", fixed: "fixed",
            geometryCornerRadius: "geometry-corner-radius", clipToGeometry: "clip-to-geometry",
            drawBorderWithBackground: "draw-border-with-background", backgroundEffect: "background-effect", blur: "blur",
            output: "output", mode: "mode", scale: "scale", transform: "transform", position: "position",
            x: "x", y: "y", vrr: "variable-refresh-rate"
        },
        hypr: {
            mod: "SUPER", bind: "hl.bind", unbind: "hl.unbind", exec: "hl.dsp.exec_cmd", config: "hl.config",
            on: "hl.on", startEvent: "hyprland.start", execNow: "hl.exec_cmd", monitor: "hl.monitor",
            windowRule: "hl.window_rule", dofile: "dofile"
        }
    })

    // ── Templates ───────────────────────────────────────────────────────────
    readonly property var defaults: ({
        // niri: settings (option paths are on the page below)
        "niri.option": "{name} {value}",
        "niri.flagOn": "{name}",
        "niri.flagOff": "{name} {@false}",
        "niri.section": "{name} {\n{body}}",
        "niri.sectionOn": "{@on}",
        "niri.sectionOff": "{@off}",
        // niri: binds
        "niri.bindsBlock": "{@binds} {\n{body}}",
        "niri.bind": "{keys}{title} { {action}; }",
        "niri.title": " {@hotkeyOverlayTitle}={title}",
        "niri.spawnSh": "{@spawnSh} {cmd}",
        "niri.disable": "{keys} {@hotkeyOverlayTitle}={@null} { {@spawn} \"true\"; }",
        "niri.keyJoin": "+",
        // niri: autostart
        "niri.autostart": "{@autostart} {cmd}",
        // niri: the settings / calendar windows
        "niri.windowRule": "{@windowRule} {\n"
            + "    {@match} {@title}={title}\n"
            + "    {@openFloating} {@true}\n"
            + "    {@defaultColumnWidth} { {@fixed} {width}; }\n"
            + "    {@defaultWindowHeight} { {@fixed} {height}; }\n"
            + "    {@geometryCornerRadius} {radius}\n"
            + "    {@clipToGeometry} {@true}\n"
            + "    {@drawBorderWithBackground} {@false}\n"
            + "{blur}}",
        // niri: the mail / calendar windows (in the layout and maximized, like a browser)
        "niri.windowRuleMaximized": "{@windowRule} {\n"
            + "    {@match} {@title}={title}\n"
            + "    {@openFloating} {@false}\n"
            + "    {@openMaximized} {@true}\n"
            + "    {@geometryCornerRadius} {radius}\n"
            + "    {@clipToGeometry} {@true}\n"
            + "    {@drawBorderWithBackground} {@false}\n"
            + "{blur}}",
        "niri.windowBlur": "    {@backgroundEffect} { {@blur} {@true}; }\n",
        // niri: monitors (quickshell-outputs.kdl)
        "niri.output": "{@output} {name} {\n{body}}",
        "niri.outputOff": "{@off}",
        "niri.outputMode": "{@mode} {mode}",
        "niri.outputScale": "{@scale} {scale}",
        "niri.outputTransform": "{@transform} {transform}",
        "niri.outputPosition": "{@position} {@x}={x} {@y}={y}",
        "niri.outputVrr": "{@vrr}",
        // niri: the line config.kdl needs
        "niri.include": "{@include} {path}",

        // Hyprland (Lua)
        "hypr.bind": "{@bind}({keys}, {action}, {opts})",
        "hypr.exec": "{@exec}({cmd})",
        "hypr.unbind": "{@unbind}({keys})",
        "hypr.autostart": "{@on}(\"{@startEvent}\", function() {@execNow}({cmd}) end)",
        "hypr.config": "{@config}({body})",
        "hypr.keyJoin": " + ",
        "hypr.monitor": "{@monitor}({ output = {output}, mode = {mode}, position = {position}, scale = {scale}, transform = {transform}, vrr = {vrr} })",
        "hypr.monitorOff": "{@monitor}({ output = {output}, disabled = true })",
        "hypr.windowRule": "{@windowRule}({\n    name = {name},\n    match = { title = {title} },\n    float = true,\n    center = true,\n    size = { {width}, {height} },\n})",
        "hypr.windowRuleMaximized": "{@windowRule}({\n    name = {name},\n    match = { title = {title} },\n    maximize = true,\n})"
    })

    // what each template is for (Syntax page)
    readonly property var docs: ({
        "niri.option": "A setting with a value: {name} from its option path, {value} (strings quoted)",
        "niri.flagOn": "A setting that's on (true)",
        "niri.flagOff": "A setting that's off (false)",
        "niri.section": "A section around settings: {name}, {body} the lines inside",
        "niri.sectionOn": "A section switched on (e.g. focus-ring)",
        "niri.sectionOff": "A section switched off",
        "niri.bindsBlock": "The binds section, {body} the binds",
        "niri.bind": "A keybind. {keys} combo, {title} the title part, {action} e.g. spawn-sh \"kitty\"",
        "niri.title": "Title shown in niri's hotkey overlay",
        "niri.spawnSh": "Run a shell command from a bind",
        "niri.disable": "Disables a bind from your config (a later bind with the same keys wins)",
        "niri.keyJoin": "Between keys of a combo",
        "niri.autostart": "Start a command at login. {cmd} the command",
        "niri.windowRule": "Window rule for the settings window (floating). {title}, {width}, {height}, {radius}, {blur} (line below)",
        "niri.windowRuleMaximized": "Window rule for the mail / calendar windows (tiled, maximized). {title}, {radius}, {blur}",
        "niri.windowBlur": "The blur line of that window rule (when \"Blur behind Quickshell windows\" is on)",
        "niri.output": "A monitor. {name} \"make model serial\", {body} its lines",
        "niri.outputOff": "Monitor turned off",
        "niri.outputMode": "Resolution + refresh, {mode} like \"2560x1440@143.973\"",
        "niri.outputScale": "Scale",
        "niri.outputTransform": "Rotation, {transform} like \"90\"",
        "niri.outputPosition": "Position, {x} {y}",
        "niri.outputVrr": "Variable refresh rate on",
        "niri.include": "The line config.kdl needs to load the shell's file, {path} quoted",
        "hypr.bind": "A keybind. {keys} combo string, {action} dispatcher, {opts} options table",
        "hypr.exec": "Dispatcher that runs a shell command",
        "hypr.unbind": "Removes a bind from your config",
        "hypr.autostart": "Start a command at login",
        "hypr.config": "Wraps the changed options, {body} a Lua table",
        "hypr.keyJoin": "Between keys of a combo",
        "hypr.monitor": "A monitor (Monitors page)",
        "hypr.monitorOff": "A monitor turned off",
        "hypr.windowRule": "Window rule for the settings window (floating)",
        "hypr.windowRuleMaximized": "Window rule for the mail / calendar windows (maximized)"
    })

    readonly property var templates: Settings.syntax.templates ?? ({})
    readonly property var words: Settings.syntax.words ?? ({})
    readonly property var paths: Settings.syntax.paths ?? ({})

    function template(name) { return templates[name] ?? defaults[name] ?? "" }
    function word(lang, w) { return words[lang + "." + w] ?? wordDefaults[lang]?.[w] ?? w }

    function fmt(name, vals) {
        const lang = name.split(".")[0]
        return template(name)
            .replace(/\{@(\w+)\}/g, (m, w) => word(lang, w))
            .replace(/\{(\w+)\}/g, (m, k) => vals && vals[k] !== undefined ? vals[k] : m)
    }

    // option path of a niri / Hyprland setting ("niri" | "hyprland", key, default path)
    function path(store, key, def) { return paths[store + "." + key] ?? def }

    function setTemplate(name, v) {
        const t = Object.assign({}, templates)
        if (v === defaults[name]) delete t[name]
        else t[name] = v
        Settings.set("syntax", "templates", t)
    }
    function setWord(lang, w, v) {
        const t = Object.assign({}, words)
        if (v === wordDefaults[lang]?.[w] || v === "") delete t[lang + "." + w]
        else t[lang + "." + w] = v
        Settings.set("syntax", "words", t)
    }
    function setPath(store, key, v, def) {
        const p = Object.assign({}, paths)
        if (v === def || v === "") delete p[store + "." + key]
        else p[store + "." + key] = v
        Settings.set("syntax", "paths", p)
    }

    // ── Key combos ──────────────────────────────────────────────────────────
    // stored as ["Mod", "Shift", "Y"] (niri names); Hyprland wants SUPER etc.
    readonly property var hyprMods: ({ mod: null, super: "SUPER", shift: "SHIFT", ctrl: "CTRL", control: "CTRL", alt: "ALT" })

    function niriKeys(keys) {
        return keys.map(k => k.toLowerCase() === "mod" ? word("niri", "mod") : k).join(template("niri.keyJoin"))
    }
    function hyprKeys(keys) {
        return keys.map(k => {
            const l = k.toLowerCase()
            if (l === "mod") return word("hypr", "mod")
            return hyprMods[l] ?? k
        }).join(template("hypr.keyJoin"))
    }

    // ── Literals ────────────────────────────────────────────────────────────
    function kdlString(s) { return JSON.stringify(String(s)) }
    function luaString(s) { return Compositor.luaString(s) }
    // JSON value → Lua literal (Hyprland dispatcher args / bind options)
    function lua(v) {
        if (v === null || v === undefined) return "nil"
        if (typeof v === "string") return luaString(v)
        if (typeof v === "number" || typeof v === "boolean") return String(v)
        if (Array.isArray(v)) return "{ " + v.map(lua).join(", ") + " }"
        const keys = Object.keys(v)
        if (keys.length === 0) return "{}"
        return "{ " + keys.map(k => (/^[A-Za-z_]\w*$/.test(k) ? k : "[" + luaString(k) + "]") + " = " + lua(v[k])).join(", ") + " }"
    }
}
