pragma Singleton
import Quickshell
import QtQuick
import qs.services

// The bits of niri / Hyprland config syntax the shell writes, as editable
// templates (settings app → Syntax). If a compositor update renames
// something small (an action, a function, an option path), it can be fixed
// there instead of in the code; every write is still validated
// (`niri validate` / `Hyprland --verify-config`), so a broken template is
// rejected and shown, not written.
//
//   fmt(name, { cmd: "\"kitty\"" })   fills {placeholders} in a template
//   path(store, key, def)             option path for a setting
//
// Placeholders get finished values: strings are already quoted for the
// target language.
Singleton {
    id: root

    readonly property var defaults: ({
        // niri (KDL)
        "niri.bind": "{keys}{title} { {action}; }",
        "niri.title": " hotkey-overlay-title={title}",
        "niri.spawnSh": "spawn-sh {cmd}",
        "niri.disable": "{keys} hotkey-overlay-title=null { spawn \"true\"; }",
        "niri.autostart": "spawn-sh-at-startup {cmd}",
        "niri.mod": "Mod",
        "niri.keyJoin": "+",
        // Hyprland (Lua)
        "hypr.bind": "hl.bind({keys}, {action}, {opts})",
        "hypr.exec": "hl.dsp.exec_cmd({cmd})",
        "hypr.unbind": "hl.unbind({keys})",
        "hypr.autostart": "hl.on(\"hyprland.start\", function() hl.exec_cmd({cmd}) end)",
        "hypr.config": "hl.config({body})",
        "hypr.mod": "SUPER",
        "hypr.keyJoin": " + "
    })

    // what each template is for (Syntax page)
    readonly property var docs: ({
        "niri.bind": "A keybind. {keys} combo, {title} the title part below, {action} e.g. spawn-sh \"kitty\"",
        "niri.title": "Title shown in niri's hotkey overlay",
        "niri.spawnSh": "Run a shell command from a bind",
        "niri.disable": "Disables a bind from your config (a later bind with the same keys wins)",
        "niri.autostart": "Start a command at login",
        "niri.mod": "Name of the main modifier",
        "niri.keyJoin": "Between keys of a combo",
        "hypr.bind": "A keybind. {keys} combo string, {action} dispatcher, {opts} options table",
        "hypr.exec": "Dispatcher that runs a shell command",
        "hypr.unbind": "Removes a bind from your config",
        "hypr.autostart": "Start a command at login",
        "hypr.config": "Wraps the changed options",
        "hypr.mod": "Name of the main modifier",
        "hypr.keyJoin": "Between keys of a combo"
    })

    readonly property var templates: Settings.syntax.templates ?? ({})
    readonly property var paths: Settings.syntax.paths ?? ({})

    function template(name) { return templates[name] ?? defaults[name] ?? "" }

    function fmt(name, vals) {
        return template(name).replace(/\{(\w+)\}/g, (m, k) => vals[k] !== undefined ? vals[k] : m)
    }

    // option path of a niri / Hyprland setting ("niri" | "hyprland", key, default path)
    function path(store, key, def) { return paths[store + "." + key] ?? def }

    function setTemplate(name, v) {
        const t = Object.assign({}, templates)
        if (v === defaults[name]) delete t[name]
        else t[name] = v
        Settings.set("syntax", "templates", t)
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
        return keys.map(k => k.toLowerCase() === "mod" ? template("niri.mod") : k).join(template("niri.keyJoin"))
    }
    function hyprKeys(keys) {
        return keys.map(k => {
            const l = k.toLowerCase()
            if (l === "mod") return template("hypr.mod")
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
