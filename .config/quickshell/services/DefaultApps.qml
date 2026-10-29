pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Default applications (settings app → Apps → Default apps): one app per
// category (browser, files, images, …), set for all of the category's types
// with `xdg-mime default` (writes ~/.config/mimeapps.list; a copy of the old
// file goes to ~/.local/state/quickshell/backups first).
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
        { id: "archives", name: "Archives", icon: "󰗄", types: ["application/zip", "application/x-tar", "application/x-7z-compressed", "application/gzip", "application/x-rar", "application/vnd.rar", "application/x-compressed-tar"] }
    ]

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
                     .concat(categories.map(cat => cat.types[0])), (code2, out2) => {
                const cur = {}
                for (const l of out2.split("\n")) {
                    const [t, app] = l.split("\t")
                    const cat = categories.find(x => x.types[0] === t)
                    if (cat) cur[cat.id] = (app ?? "").trim()
                }
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
    }

    function entry(app) { return DesktopEntries.byId(app.replace(/\.desktop$/, "")) }
    function name(app) { return entry(app)?.name ?? app.replace(/\.desktop$/, "") }
    function icon(app) { const i = entry(app)?.icon ?? ""; return i ? Quickshell.iconPath(i, true) : "" }

    // set `app` for every type of the category
    function set(catId, app, cb) {
        const cat = categories.find(c => c.id === catId)
        if (!cat || !/^[A-Za-z0-9._+-]+\.desktop$/.test(app) || !(candidates[catId] ?? []).includes(app)) return cb && cb(false)
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
