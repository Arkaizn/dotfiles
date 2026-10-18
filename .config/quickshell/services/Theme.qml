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
    Component.onCompleted: hasUndo = read(undoFile) !== ""

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

    IpcHandler {
        target: "theme"
        function apply(file: string): string { root.apply(file); return "applying " + file }
        function undo(): string { if (!root.hasUndo) return "nothing to undo"; root.undo(); return "undoing" }
    }
}
