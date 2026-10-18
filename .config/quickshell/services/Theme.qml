pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// pywal themes (settings app → Shell → Theme): preview a scheme before it's
// applied, light / dark, saved themes and pywal's built-in ones.
//
// A preview runs wal with PYWAL_CACHE_DIR pointed at a scratch folder (and
// -n -s -t -e: no wallpaper, terminals, tty or reloads), so nothing you use
// changes until you press Apply. Apply = `wal --theme <file> -n` + niri's
// border colors (niri-colors.sh); the previous colors.json is kept for Undo.
//
//   qs ipc call theme apply <file.json>    qs ipc call theme undo
//   qs ipc call theme mode light|dark|toggle
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string previewDir: runtime + "/quickshell-theme-preview"
    readonly property string savedDir: home + "/.local/share/quickshell/themes"
    readonly property string undoFile: home + "/.local/state/quickshell/theme-undo.json"
    readonly property string currentFile: home + "/.cache/wal/colors.json"
    readonly property string niriColors: home + "/.config/niri/niri-colors.sh"

    // the wallpaper the current colors came from
    readonly property string wallpaper: current?.wallpaper ?? (home + "/.local/share/backgrounds/pywallpaper.png")
    property var current: null             // parsed ~/.cache/wal/colors.json
    property var preview: null             // { name, file, colors: {color0..15}, special: {background, foreground, cursor} }
    property bool applying: false
    property bool hasUndo: false
    property string error: ""
    property var backends: ["wal"]         // the ones whose python module is installed
    property var saved: []                 // [{ name, file, data }]
    property var builtins: []              // [{ name, file, light, data }]
    readonly property bool previewing: Jobs.isRunning("theme-preview")

    // so `qs ipc call theme undo` knows about the undo file right after startup
    Component.onCompleted: { hasUndo = read(undoFile) !== ""; detect() }

    function refresh() {
        current = parse(read(currentFile))
        hasUndo = read(undoFile) !== ""
        listSaved()
    }

    // ── files ───────────────────────────────────────────────────────────────
    FileView { id: reader; blockLoading: true; printErrors: false }
    function read(p) { reader.path = ""; reader.path = p; return reader.text() ?? "" }
    function parse(text) {
        try {
            const j = JSON.parse(text)
            if (!j.colors || !/^#[0-9a-f]{6}$/i.test(j.colors.color0 ?? "")) return null
            return j
        } catch (e) { return null }
    }

    // ── preview ─────────────────────────────────────────────────────────────
    // opts: { light, backend, saturate (0–1 or -1 = default), image }
    function previewWallpaper(opts) {
        error = ""
        const img = opts.image || wallpaper
        const args = ["wal", "-i", img, "-n", "-s", "-t", "-e", "-q", "--backend", opts.backend || "wal"]
        if (opts.light) args.push("-l")
        if (opts.saturate >= 0) args.push("--saturate", String(opts.saturate))
        Jobs.run(["rm", "-rf", "--", previewDir], () => Jobs.run(["mkdir", "-p", "--", previewDir], () =>
            Jobs.start("theme-preview", args, {
                timeout: 60000, env: { PYWAL_CACHE_DIR: previewDir },
                onExit: code => {
                    const st = Jobs.state("theme-preview")
                    if (st.missing) { error = "wal isn't installed: " + Jobs.installHint("wal"); return }
                    const j = code === 0 ? parse(read(previewDir + "/colors.json")) : null
                    if (!j) { error = st.timedOut ? "wal took too long" : (st.lines.filter(l => l.err).map(l => l.text).slice(-2).join(" ") || "wal failed (exit " + code + ")"); return }
                    preview = { name: (opts.light ? "light" : "dark") + " · " + (opts.backend || "wal") + (opts.saturate >= 0 ? " · saturation " + opts.saturate : ""),
                                file: previewDir + "/colors.json", colors: j.colors, special: j.special }
                }
            })))
    }
    function cancelPreview() { Jobs.cancel("theme-preview") }

    // data: the parsed theme if the caller has it already (lists), else the file is read
    function previewFile(name, file, data) {
        error = ""
        const j = data ?? parse(read(file))
        if (!j) { error = name + " isn't a pywal theme"; return }
        preview = { name: name, file: file, colors: j.colors, special: j.special }
    }

    // ── apply / undo ────────────────────────────────────────────────────────
    function apply(file, cb) {
        if (applying) return
        applying = true
        error = ""
        // the file may be the preview (in the runtime dir); keep a stable copy
        const src = runtime + "/quickshell-theme-apply.json"
        Jobs.run(["mkdir", "-p", "--", home + "/.local/state/quickshell"], () =>
        Jobs.run(["cp", "--", file, src], c0 => {
            if (c0 !== 0) return done(false, "can't read " + file)
            Jobs.run(["cp", "--", currentFile, undoFile], () =>
            Jobs.run(["wal", "--theme", src, "-n", "-q"], (code, out, err) => {
                if (code !== 0) return done(false, err.trim().split("\n").slice(-1)[0] || "wal failed (exit " + code + ")")
                Jobs.run(["bash", niriColors], () => done(true, ""))
            }))
        }))
        function done(ok, msg) {
            applying = false
            error = msg
            refresh()
            if (cb) cb(ok)
        }
    }
    function undo() { if (hasUndo) apply(undoFile) }

    // ── saved themes ────────────────────────────────────────────────────────
    function validName(n) {
        n = String(n ?? "").trim()
        if (n === "") return "enter a name"
        if (!/^[A-Za-z0-9 _-]{1,40}$/.test(n)) return "letters, digits, space, _ and - (max 40)"
        return ""
    }
    // all files in one go (one FileView read per file in a loop returns stale text)
    function listSaved() {
        Jobs.run(["sh", "-c", 'for f in "$1"/*.json; do [ -f "$f" ] && printf "\\036%s\\n" "$f" && tr "\\n" " " < "$f" && echo; done', "sh", savedDir], (code, out) => {
            const t = []
            for (const chunk of out.split("\x1e").filter(c => c.trim())) {
                const nl = chunk.indexOf("\n")
                const f = chunk.slice(0, nl), data = parse(chunk.slice(nl + 1))
                if (data) t.push({ name: f.replace(/.*\//, "").replace(/\.json$/, ""), file: f, data: data })
            }
            saved = t
        })
    }
    function save(name, cb) {
        const e = validName(name)
        if (e) return cb(false, e)
        name = name.trim()
        Jobs.run(["mkdir", "-p", "--", savedDir], () => Jobs.run(["cp", "--", currentFile, savedDir + "/" + name + ".json"], code => {
            listSaved()
            cb(code === 0, code === 0 ? "" : "couldn't write " + savedDir)
        }))
    }
    function remove(name) {
        if (validName(name)) return
        Jobs.run(["rm", "-f", "--", savedDir + "/" + name + ".json"], () => listSaved())
    }

    // ── pywal's built-in themes / installed backends ────────────────────────
    function loadBuiltins() {
        if (builtins.length > 0) return
        Jobs.run(["python3", "-c",
                  "import pywal, os, json, importlib.util as u\n"
                + "d = os.path.join(os.path.dirname(pywal.__file__), 'colorschemes')\n"
                + "for k in ('dark', 'light'):\n"
                + "    for f in sorted(os.listdir(os.path.join(d, k))):\n"
                + "        if not f.endswith('.json'): continue\n"
                + "        p = os.path.join(d, k, f)\n"
                + "        try: print('T', k, json.dumps({'file': p, 'data': json.load(open(p))}))\n"
                + "        except Exception: pass\n"
                + "for b in ('colorz', 'haishoku', 'colorthief', 'fast_colorthief', 'modern_colorthief'):\n"
                + "    if u.find_spec(b): print('B', b)\n"], (code, out) => {
            const t = [], b = ["wal"]
            for (const l of out.split("\n")) {
                const m = /^T (dark|light) (.+)$/.exec(l)
                if (m) {
                    try {
                        const j = JSON.parse(m[2])
                        if (j.data?.colors?.color0)
                            t.push({ name: j.file.replace(/.*\//, "").replace(/\.json$/, ""), file: j.file, light: m[1] === "light", data: j.data })
                    } catch (e) {}
                }
                const n = /^B (\S+)$/.exec(l)
                if (n) b.push(n[1])
            }
            builtins = t
            backends = b
        })
    }

    // ── Light / dark mode (scripts/color-mode.sh) ───────────────────────────
    // Settings.theme: mode, the parts to switch (wal, niri, portal, gtk, icons, qt)
    // and the theme pairs (gtkLight / gtkDark, iconLight / iconDark, kvLight / kvDark,
    // qtColorsLight / qtColorsDark). Missing pairs: detected from the current setup.
    readonly property string modeScript: home + "/.config/quickshell/scripts/color-mode.sh"
    readonly property string mode: Settings.theme.mode ?? (Colors.light ? "light" : "dark")
    readonly property bool switching: Jobs.isRunning("color-mode")
    property var detected: ({})            // { gtk, icons, kvantum, qtColors } as set now
    property var themes: ({ gtk: [], icons: [], kvantum: [] })   // installed, for the pickers

    function part(k) { return Settings.theme[k] ?? true }
    // light / dark name for a part: the setting, else derived from what's set now
    function pair(kind, m) {
        const key = kind + (m === "light" ? "Light" : "Dark")
        if (Settings.theme[key]) return Settings.theme[key]
        const cur = detected[kind] ?? ""
        const list = themes[kind] ?? []
        const isDark = /dark/i.test(cur)
        if ((m === "dark") === isDark || cur === "") return cur
        if (kind === "qtColors") return m === "light" ? "/usr/share/qt6ct/colors/airy.conf" : "/usr/share/qt6ct/colors/darker.conf"
        // Colloid-Dark → Colloid-Light / Colloid · Fluent-dark → Fluent · Fluent-roundDark → Fluent-round
        const base = cur.replace(/[-_]?(dark|light)$/i, "")
        // icons: the plain name is the light variant (Fluent-light is for light panels on dark apps)
        if (m === "light") return (kind === "icons" ? [base, base + "-Light", base + "-light"] : [base + "-Light", base + "-light", base]).find(n => list.includes(n)) ?? base
        return [base + "-Dark", base + "-dark", base + "Dark"].find(n => list.includes(n)) ?? cur
    }

    function detect() {
        Jobs.run(["sh", "-c",
                  'printf "gtk\t%s\n" "$(gsettings get org.gnome.desktop.interface gtk-theme)"\n'
                + 'printf "icons\t%s\n" "$(gsettings get org.gnome.desktop.interface icon-theme)"\n'
                + 'c=${XDG_CONFIG_HOME:-$HOME/.config}\n'
                + 'printf "kvantum\t%s\n" "$(sed -n "s/^theme=//p" "$c/Kvantum/kvantum.kvconfig" 2>/dev/null)"\n'
                + 'printf "qtColors\t%s\n" "$(sed -n "s/^color_scheme_path=//p" "$c/qt6ct/qt6ct.conf" 2>/dev/null)"\n'
                + 'for d in "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes; do for t in "$d"/*/; do [ -d "$t/gtk-3.0" ] && printf "T\tgtk\t%s\n" "$(basename "$t")"; done; done\n'
                + 'for d in "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons; do for t in "$d"/*/; do [ -f "$t/index.theme" ] && printf "T\ticons\t%s\n" "$(basename "$t")"; done; done\n'
                + 'for d in "$c/Kvantum" /usr/share/Kvantum; do for t in "$d"/*/; do for k in "$t"*.kvconfig; do [ -f "$k" ] && printf "T\tkvantum\t%s\n" "$(basename "$k" .kvconfig)"; done; done; done'],
                (code, out) => {
            const d = {}, t = { gtk: [], icons: [], kvantum: [] }
            for (const l of out.split("\n")) {
                const p = l.split("\t")
                if (p[0] === "T" && t[p[1]] && !t[p[1]].includes(p[2])) t[p[1]].push(p[2])
                else if (p.length === 2) d[p[0]] = p[1].replace(/^'|'$/g, "")
            }
            for (const k in t) t[k].sort()
            themes = t
            detected = d
        })
    }

    function validTheme(n) { return /^[A-Za-z0-9 ._+-]{1,80}$/.test(n) }

    // m: "light" | "dark"
    function setMode(m) {
        if (m !== "light" && m !== "dark" || switching) return
        const args = ["bash", modeScript, m]
        if (part("wal")) args.push("--wal")
        if (part("niri")) args.push("--niri")
        if (part("portal")) args.push("--portal")
        const add = (flag, kind) => { const n = pair(kind, m); if (n && validTheme(n)) args.push(flag, n) }
        if (part("gtk")) add("--gtk", "gtk")
        if (part("icons")) add("--icons", "icons")
        if (part("qt")) {
            add("--kvantum", "kvantum")
            const c = pair("qtColors", m)
            if (c && /^\/[A-Za-z0-9 ._\/-]+\.conf$/.test(c)) args.push("--qtcolors", c)
        }
        // remember the pairs as they are now, so later guesses don't depend on the mode
        for (const k of ["gtk", "icons", "kvantum", "qtColors"])
            for (const mm of ["Light", "Dark"])
                if (!Settings.theme[k + mm] && pair(k, mm.toLowerCase())) Settings.set("theme", k + mm, pair(k, mm.toLowerCase()))
        Settings.set("theme", "mode", m)
        Jobs.start("color-mode", args, { timeout: 120000, onExit: () => { refresh(); detect() } })
    }

    IpcHandler {
        target: "theme"
        function mode(m: string): string {
            const target = m === "toggle" || m === "" ? (root.mode === "dark" ? "light" : "dark") : m
            if (target !== "light" && target !== "dark") return "light, dark or toggle"
            root.setMode(target)
            return "switching to " + target
        }
        function apply(file: string): string { root.apply(file); return "applying " + file }
        function undo(): string { if (!root.hasUndo) return "nothing to undo"; root.undo(); return "undoing" }
    }
}
