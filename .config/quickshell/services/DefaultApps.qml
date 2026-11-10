pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Default applications (settings app → Apps → Default apps): one app per
// category (browser, files, images, …), set for all of the category's types
// with `xdg-mime default` (writes ~/.config/mimeapps.list; a copy of the old
// file goes to ~/.local/state/quickshell/backups first).
//
// Terminal is no MIME type: it's the first installed entry of xdg-terminals.list
// (the xdg-terminal-exec standard; $XDG_CURRENT_DESKTOP-xdg-terminals.list first),
// candidates are the apps with Categories=TerminalEmulator. Setting it puts the app
// first in that file. Apps open things in it with
//   DefaultApps.inTerminal(title, argv)          (falls back to kitty)
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string mimeapps: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/mimeapps.list"
    readonly property string backupDir: home + "/.local/state/quickshell/backups"

    // first type = the one whose current default is shown
    readonly property var categories: [
        { id: "browser", name: "Web browser", icon: "󰖟", types: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"] },
        { id: "files", name: "File manager", icon: "󰉋", types: ["inode/directory"] },
        { id: "text", name: "Text editor", icon: "󰈙", types: ["text/plain", "text/markdown", "application/x-shellscript", "application/json", "text/x-csrc", "text/x-python"] },
        { id: "images", name: "Images", icon: "󰋩", types: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff", "image/avif"] },
        { id: "video", name: "Video", icon: "󰕧", types: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg"] },
        { id: "music", name: "Music", icon: "󰝚", types: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac"] },
        { id: "pdf", name: "PDF", icon: "󰈦", types: ["application/pdf"] },
        { id: "mail", name: "Email", icon: "󰇮", types: ["x-scheme-handler/mailto"] },
        { id: "archives", name: "Archives", icon: "󰗄", types: ["application/zip", "application/x-tar", "application/x-7z-compressed", "application/gzip", "application/x-rar", "application/vnd.rar", "application/x-compressed-tar"] },
        { id: "terminal", name: "Terminal", icon: "󰆍", types: [], file: "xdg-terminals.list" }
    ]
    readonly property var mimeCategories: categories.filter(c => c.types.length > 0)

    // ── Terminal (xdg-terminals.list) ────────────────────────────────────────
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string desktopName: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").split(":")[0].toLowerCase()
    // the list files, most specific first (only the existing ones count)
    readonly property var terminalLists: (desktopName ? [configDir + "/" + desktopName + "-xdg-terminals.list"] : []).concat([configDir + "/xdg-terminals.list"])
    readonly property string listTerminalsScript:
        'for d in "$@"; do [ -d "$d" ] || continue; for f in "$d"/*.desktop; do\n'
        + '  grep -q "^Categories=.*TerminalEmulator" "$f" 2>/dev/null || continue\n'
        + '  grep -q "^NoDisplay=true" "$f" && continue\n'
        + '  printf "%s\\n" "${f##*/}"; done; done'
    // the configured terminal: first line of the first list file that names an installed app
    readonly property string currentTerminalScript:
        'for l in "$@"; do [ -f "$l" ] || continue; while IFS= read -r a; do a=${a%%:*}; a=${a%%#*}; a=$(printf %s "$a" | tr -d "[:space:]")\n'
        + '  case "$a" in ""|+*|-*) continue ;; esac\n'
        + '  for d in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications; do\n'
        + '    [ -f "$d/$a" ] && { printf "%s\\n" "$a"; exit 0; }; done; done < "$l"; done'

    // cb("app.desktop" | "")
    function terminalApp(cb) {
        Jobs.run(["sh", "-c", currentTerminalScript, "sh"].concat(terminalLists), (code, out) => cb(out.trim()))
    }

    // argv to run `argv` in a terminal app, with a window title
    function terminalArgv(app, title, argv) {
        const known = {
            "kitty.desktop": ["kitty", "--title", title, "--"],
            "org.gnome.Terminal.desktop": ["gnome-terminal", "--title", title, "--"],
            "org.gnome.Console.desktop": ["kgx", "--title", title, "--"],
            "org.kde.konsole.desktop": ["konsole", "-p", "tabtitle=" + title, "-e"],
            "Alacritty.desktop": ["alacritty", "--title", title, "-e"],
            "foot.desktop": ["foot", "--title", title, "--"],
            "com.mitchellh.ghostty.desktop": ["ghostty", "--title=" + title, "-e"],
            "org.wezfurlong.wezterm.desktop": ["wezterm", "start", "--"],
            "xfce4-terminal.desktop": ["xfce4-terminal", "--title", title, "-x"]
        }
        if (known[app]) return known[app].concat(argv)
        // anything else: its program with the usual -e
        const exec = (entry(app)?.command ?? [])[0]
        return exec ? [exec, "-e"].concat(argv) : ["kitty", "--title", title, "--"].concat(argv)
    }

    // run argv in the default terminal (Settings → Default apps → Terminal; kitty when unset)
    function inTerminal(title, argv) {
        terminalApp(app => Jobs.detached(terminalArgv(app || "kitty.desktop", title, argv), null))
    }

    // make `app` the default terminal: first line of the list file in use (the
    // desktop's own one if it exists), the old entries after it
    function setTerminal(app, cb) {
        Jobs.run(["sh", "-c", 'for l in "$@"; do [ -f "$l" ] && { printf %s "$l"; exit; }; done; printf %s "$1"', "sh"].concat(terminalLists), (c0, file) => {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
            Jobs.run(["sh", "-c", 'mkdir -p -- "$3" && { [ ! -f "$1" ] || cp -p -- "$1" "$3/${1##*/}.$4"; }\n'
                    + 'tmp=$(mktemp) && { printf "%s\\n" "$2"; [ -f "$1" ] && grep -vxF -- "$2" "$1"; } > "$tmp" && cat "$tmp" > "$1"; rc=$?; rm -f "$tmp"; exit $rc',
                      "sh", file.trim() || terminalLists[terminalLists.length - 1], app, backupDir, stamp], (code, out, err) => {
                if (code !== 0) error = err.trim() || "couldn't write the terminal list"
                refresh()
                if (cb) cb(code === 0)
            })
        })
    }

    property var current: ({})             // category id → "app.desktop" ("" = none)
    property var candidates: ({})          // category id → ["app.desktop", …]
    property bool loading: false
    property string error: ""

    function refresh(done) {
        loading = true
        error = ""
        // desktop files and the types they open (all application dirs, user first)
        const dataDirs = [(Quickshell.env("XDG_DATA_HOME") || home + "/.local/share")]
                         .concat((Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":"))
                         .map(d => d + "/applications")
        Jobs.run(["sh", "-c", 'for d in "$@"; do [ -d "$d" ] && grep -H "^MimeType=" "$d"/*.desktop 2>/dev/null; done', "sh"].concat(dataDirs), (code, out) => {
            const c = {}
            for (const cat of categories) c[cat.id] = []
            for (const l of out.split("\n")) {
                const m = /\/([^/]+\.desktop):MimeType=(.*)$/.exec(l)
                if (!m) continue
                const types = m[2].split(";")
                for (const cat of categories)
                    if (cat.types.some(t => types.includes(t)) && !c[cat.id].includes(m[1])) c[cat.id].push(m[1])
            }
            // the current default first query
            Jobs.run(["sh", "-c", 'for t in "$@"; do printf "%s\\t%s\\n" "$t" "$(xdg-mime query default "$t" 2>/dev/null)"; done', "sh"]
                     .concat(mimeCategories.map(cat => cat.types[0])), (code2, out2) => {
                const cur = {}
                for (const l of out2.split("\n")) {
                    const [t, app] = l.split("\t")
                    const cat = mimeCategories.find(x => x.types[0] === t)
                    if (cat) cur[cat.id] = (app ?? "").trim()
                }
                Jobs.run(["sh", "-c", listTerminalsScript, "sh"].concat(dataDirs), (c3, out3) => {
                c.terminal = out3.split("\n").filter(x => x !== "").filter((x, i, a) => a.indexOf(x) === i)
                terminalApp(term => {
                cur.terminal = term
                for (const cat of categories) {
                    const a = cur[cat.id]
                    if (a && !c[cat.id].includes(a)) c[cat.id].unshift(a)
                    c[cat.id].sort((x, y) => name(x).localeCompare(name(y)))
                }
                candidates = c
                current = cur
                loading = false
                if (typeof done === "function") done()
                })
                })
            })
        })
    }

    function entry(app) { return DesktopEntries.byId(app.replace(/\.desktop$/, "")) }
    function name(app) { return entry(app)?.name ?? app.replace(/\.desktop$/, "") }
    function icon(app) { const i = entry(app)?.icon ?? ""; return i ? Quickshell.iconPath(i, true) : "" }

    // set `app` for every type of the category
    function set(catId, app, cb) {
        const cat = categories.find(c => c.id === catId)
        if (!cat || !/^[A-Za-z0-9._+-]+\.desktop$/.test(app) || !(candidates[catId] ?? []).includes(app)) return cb && cb(false)
        if (catId === "terminal") return setTerminal(app, cb)
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
        Jobs.run(["mkdir", "-p", "--", backupDir], () =>
        Jobs.run(["sh", "-c", '[ ! -f "$1" ] || cp -p -- "$1" "$2"', "sh", mimeapps, backupDir + "/mimeapps.list." + stamp], () =>
        Jobs.run(["xdg-mime", "default", app].concat(cat.types), (code, out, err) => {
            if (code !== 0) error = err.trim() || "xdg-mime failed"
            refresh()
            if (cb) cb(code === 0)
        })))
    }
}
