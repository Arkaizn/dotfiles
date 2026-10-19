pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Settings profiles (settings app → Shell → Profiles): named snapshots of
// chosen settings groups (+ optionally the pywal colors), e.g. "Work" /
// "Gaming", switched in one go.
//
// ~/.local/share/quickshell/profiles/<name>.json:
//   { name, saved, icon, settings: { group: {…} }, colors: {pywal colors.json} | null }
//   (icon: a Nerd Font glyph for the switcher at the bottom of the settings
//   sidebar; none = the name's first letter)
// Export: one file with any number of profiles
//   { quickshellProfiles: 1, exported, profiles: [ <profile>, … ] }
// Import takes such files and single profile files, checks every profile like
// an import of settings, then writes them (same name = replaced).
// Applying checks the file with the same validation as an import (the
// settings window registers it as `validator`), keeps the current values of
// those groups for Undo, then replaces only the groups in the profile.
//
//   qs ipc call profiles list | apply <name> | undo
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.local/share/quickshell/profiles"
    readonly property string undoFile: home + "/.local/state/quickshell/profile-undo.json"
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    // groups that describe this machine rather than taste: off by default
    readonly property var deviceGroups: ["monitors", "connections", "dotfiles", "settingsProfiles", "wizard", "health"]
    function defaultGroups() { return Settings.groups.filter(g => !deviceGroups.includes(g) && Object.keys(Settings[g] ?? {}).length > 0) }

    property var profiles: []               // [{ name, file, saved, icon, groups, hasColors }]
    // a few icons to pick from (any glyph works in the file)
    readonly property var iconChoices: ["󰆓", "󰃖", "󰊗", "󰎆", "󰈹", "󰖔", "󰖙", "󰌢", "󰋜", "󰠮", "󰐱", "󱓞", "󰏘", "󰉋", "󰇄", "󰓅"]
    readonly property string active: Settings.settingsProfiles.active ?? ""
    property bool hasUndo: false
    property string error: ""
    // fn(settingsObject) → [{ message }] (set by the settings window)
    property var validator: null

    function validName(n) {
        n = String(n ?? "").trim()
        if (n === "") return "enter a name"
        if (!/^[A-Za-z0-9 _-]{1,40}$/.test(n)) return "letters, digits, space, _ and - (max 40)"
        return ""
    }

    function refresh() {
        Jobs.run(["sh", "-c", 'for f in "$1"/*.json; do [ -f "$f" ] && printf "\\036%s\\n" "$f" && tr "\\n" " " < "$f" && echo; done', "sh", dir], (code, out) => {
            const list = []
            for (const chunk of out.split("\x1e").filter(c => c.trim())) {
                const nl = chunk.indexOf("\n")
                try {
                    const p = JSON.parse(chunk.slice(nl + 1))
                    list.push({ name: chunk.slice(0, nl).replace(/.*\//, "").replace(/\.json$/, ""), file: chunk.slice(0, nl),
                                saved: p.saved ?? "", icon: typeof p.icon === "string" ? p.icon : "",
                                groups: Object.keys(p.settings ?? {}), hasColors: !!p.colors })
                } catch (e) {
                    list.push({ name: chunk.slice(0, nl).replace(/.*\//, "").replace(/\.json$/, ""), file: chunk.slice(0, nl), broken: true, groups: [] })
                }
            }
            profiles = list.sort((a, b) => a.name.localeCompare(b.name))
        })
        hasUndo = NiriSettings.readFile(undoFile) !== ""
    }
    Component.onCompleted: refresh()

    function write(path, obj, cb) {
        Jobs.runInput(["sh", "-c", 'mkdir -p -- "$(dirname -- "$1")" && cat > "$1"', "sh", path], JSON.stringify(obj, null, 2) + "\n", code => cb(code === 0))
    }

    function read(name) {
        try { return JSON.parse(NiriSettings.readFile(dir + "/" + name + ".json")) } catch (x) { return null }
    }

    // icon: undefined = keep the one it has
    function save(name, groups, withColors, cb, icon) {
        const e = validName(name)
        if (e) return cb(false, e)
        name = name.trim()
        if (icon === undefined) icon = read(name)?.icon ?? ""
        const settings = {}
        for (const g of groups) if (Settings.groups.includes(g)) settings[g] = Settings[g] ?? {}
        let colors = null
        if (withColors) { try { colors = JSON.parse(NiriSettings.readFile(home + "/.cache/wal/colors.json")) } catch (x) { colors = null } }
        write(dir + "/" + name + ".json", { name: name, saved: new Date().toISOString(), icon: icon, settings: settings, colors: colors }, ok => {
            refresh()
            cb(ok, ok ? "" : "couldn't write " + dir)
        })
    }

    function setIcon(name, icon) {
        const p = read(name)
        if (!p || validName(name)) return
        p.icon = icon
        write(dir + "/" + name + ".json", p, () => refresh())
    }

    // ── Export / import ──────────────────────────────────────────────────────
    // cb(ok, message)
    function exportTo(path, names, cb) {
        const list = names.map(n => read(n)).filter(p => p)
        if (list.length === 0) return cb(false, "nothing to export")
        write(path, { quickshellProfiles: 1, exported: new Date().toISOString(), profiles: list },
              ok => cb(ok, ok ? list.length + (list.length === 1 ? " profile" : " profiles") + " exported to " + path : "couldn't write " + path))
    }

    // checks one profile object → "" or what's wrong with it
    function checkProfile(p) {
        if (!p || typeof p !== "object" || Array.isArray(p)) return "not a profile { … }"
        const n = validName(p.name)
        if (n) return "name: " + n
        if (p.icon !== undefined && (typeof p.icon !== "string" || p.icon.length > 8)) return "icon must be a short text (one glyph)"
        if (p.colors !== undefined && p.colors !== null && (typeof p.colors !== "object" || Array.isArray(p.colors) || typeof p.colors.colors !== "object"))
            return "colors must be a pywal colors.json or null"
        const s = p.settings
        if (!s || typeof s !== "object" || Array.isArray(s)) return "no settings in it"
        if (!validator) return "open the settings app once (it provides the checks)"
        const errs = validator(s)
        return errs.length === 0 ? "" : errs.slice(0, 3).map(x => x.message).join("; ") + (errs.length > 3 ? " (+" + (errs.length - 3) + " more)" : "")
    }

    // files → [{ name, profile, problem, exists, file }] (problem "" = can be imported)
    function readImport(paths) {
        const out = []
        for (const path of paths) {
            const file = path.replace(/.*\//, "")
            let o
            try { o = JSON.parse(NiriSettings.readFile(path)) }
            catch (x) { out.push({ name: file, file: file, problem: "isn't valid JSON" }); continue }
            const list = Array.isArray(o?.profiles) ? o.profiles : [o]
            if (o?.quickshellSettings !== undefined) { out.push({ name: file, file: file, problem: "is a settings export (use Import at the top of the sidebar)" }); continue }
            for (const p of list) {
                const name = String(p?.name ?? "").trim()
                out.push({ name: name || "?", file: file, profile: p, problem: checkProfile(p), exists: profiles.some(x => x.name === name) })
            }
        }
        // the same name twice: the last one wins
        return out.filter((e, i) => e.problem !== "" || !out.slice(i + 1).some(x => x.problem === "" && x.name === e.name))
    }

    // writes the good ones of readImport(); cb(count)
    function importProfiles(list, cb) {
        const good = list.filter(e => e.problem === "")
        let left = good.length, okCount = 0
        if (left === 0) return cb(0)
        for (const e of good) {
            const p = e.profile
            write(dir + "/" + e.name + ".json", { name: e.name, saved: p.saved ?? new Date().toISOString(), icon: p.icon ?? "",
                                                   settings: p.settings, colors: p.colors ?? null }, ok => {
                if (ok) okCount++
                if (--left === 0) { refresh(); cb(okCount) }
            })
        }
    }

    function remove(name) {
        if (validName(name)) return
        Jobs.run(["rm", "-f", "--", dir + "/" + name + ".json"], () => refresh())
    }

    // cb(ok, message)
    function apply(name, cb) {
        cb = cb ?? (() => {})
        if (validName(name)) return cb(false, "bad name")
        let p
        try { p = JSON.parse(NiriSettings.readFile(dir + "/" + name.trim() + ".json")) } catch (x) { return cb(false, name + ".json isn't valid JSON") }
        applyObject(p, ok => { if (ok) Settings.set("settingsProfiles", "active", name.trim()) ; cb(ok, ok ? "" : error) })
    }

    function applyObject(p, cb) {
        error = ""
        const s = p?.settings
        if (!s || typeof s !== "object" || Array.isArray(s)) { error = "no settings in the profile"; return cb(false) }
        if (validator) {
            const errs = validator(s)
            if (errs.length > 0) { error = errs.slice(0, 4).map(x => x.message).join("; "); return cb(false) }
        } else { error = "open the settings app once (it provides the checks)"; return cb(false) }
        // undo: the current values of exactly these groups (+ colors if the profile has some)
        const undo = { name: "undo", settings: {}, colors: null }
        for (const g of Object.keys(s)) undo.settings[g] = Settings[g] ?? {}
        if (p.colors) { try { undo.colors = JSON.parse(NiriSettings.readFile(home + "/.cache/wal/colors.json")) } catch (x) {} }
        write(undoFile, undo, ok => {
            if (!ok) { error = "couldn't write the undo file"; return cb(false) }
            for (const g of Object.keys(s)) Settings.setGroup(g, s[g])
            if (s.monitors !== undefined) Monitors.write()
            hasUndo = true
            if (p.colors) {
                const f = runtime + "/quickshell-profile-colors.json"
                write(f, p.colors, ok2 => { if (ok2) Theme.apply(f); cb(true) })
            } else cb(true)
        })
    }

    function undo(cb) {
        cb = cb ?? (() => {})
        let p
        try { p = JSON.parse(NiriSettings.readFile(undoFile)) } catch (x) { return cb(false) }
        applyObject(p, ok => { if (ok) Settings.set("settingsProfiles", "active", ""); cb(ok) })
    }

    IpcHandler {
        target: "profiles"
        function list(): string { return root.profiles.map(p => p.name + (p.name === root.active ? " (active)" : "")).join("\n") }
        function apply(name: string): string {
            if (!root.profiles.some(p => p.name === name)) return "no profile named " + name
            root.apply(name, (ok, msg) => {})
            return root.error === "" ? "applying " + name : root.error
        }
        function undo(): string { root.undo(); return root.hasUndo ? "undoing" : "nothing to undo" }
    }
}
