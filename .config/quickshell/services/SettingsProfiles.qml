pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Settings profiles (settings app → Shell → Profiles): named snapshots of
// chosen settings groups (+ optionally the pywal colors), e.g. "Work" /
// "Gaming", switched in one go.
//
// ~/.local/share/quickshell/profiles/<name>.json:
//   { name, saved, groups: [...], settings: { group: {…} }, colors: {pywal colors.json} | null }
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

    property var profiles: []               // [{ name, file, saved, groups, hasColors }]
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
                                saved: p.saved ?? "", groups: Object.keys(p.settings ?? {}), hasColors: !!p.colors })
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

    function save(name, groups, withColors, cb) {
        const e = validName(name)
        if (e) return cb(false, e)
        name = name.trim()
        const settings = {}
        for (const g of groups) if (Settings.groups.includes(g)) settings[g] = Settings[g] ?? {}
        let colors = null
        if (withColors) { try { colors = JSON.parse(NiriSettings.readFile(home + "/.cache/wal/colors.json")) } catch (x) { colors = null } }
        write(dir + "/" + name + ".json", { name: name, saved: new Date().toISOString(), settings: settings, colors: colors }, ok => {
            refresh()
            cb(ok, ok ? "" : "couldn't write " + dir)
        })
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
