pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// The wallpaper folder and setting a wallpaper (Launcher → Wallpapers).
//
//   Wallpapers.scan()                 find the images in ~/Pictures/Wallpapers (recursive)
//   Wallpapers.items                  [{ path, name, relDir }] sorted by path
//   Wallpapers.apply(path)            copy it to the pywal wallpaper and run set_wallpaper.sh
//   Wallpapers.stop()                 kill that whole command (process group)
//   Wallpapers.thumbFor(path)         cached thumbnail file (exists or not)
//   Wallpapers.hasThumb(path)         whether that file exists (from one listing per scan)
//   Wallpapers.thumbSaved(path)       a tile saved a new thumbnail
//
// Paths go in as arguments only (positional parameters for the one shell
// that's needed for `cp && bash`), never pasted into a command string — a file
// name with a ' or $( ) in a downloaded wallpaper pack is just a name.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string outputPath: Quickshell.env("HOME") + "/.local/share/backgrounds/pywallpaper.png"
    readonly property string scriptPath: Quickshell.shellDir + "/scripts/set_wallpaper.sh"
    readonly property string thumbDir: Quickshell.cachePath("wallpaper_thumbs")   // persists across restarts

    property var items: []
    property bool scanned: false
    readonly property bool scanning: _scanning
    property bool _scanning: false
    property var thumbs: ({})                // cached thumbnail file names (hash.png) → true

    readonly property bool applying: applyProc.running
    property string pickedPath: ""
    // last result for the picker's status line: { text, tone: "muted" | "info" | "ok" | "warn" | "error" }
    property var status: ({ text: "", tone: "info" })
    signal statusShown()

    function setStatus(text, tone) { status = { text: text, tone: tone }; statusShown() }

    function relDirOf(full) {
        let rel = full.indexOf(dir) === 0 ? full.substring(dir.length) : full
        if (rel.charAt(0) === "/") rel = rel.substring(1)
        const i = rel.lastIndexOf("/")
        return i >= 0 ? rel.substring(0, i) : ""
    }

    function scan() {
        if (_scanning) return
        _scanning = true
        setStatus("Scanning…", "muted")
        Jobs.run(["mkdir", "-p", thumbDir], () => {
            // the thumbnail cache once, instead of a `test -f` per tile
            Jobs.run(["find", thumbDir, "-maxdepth", "1", "-type", "f", "-name", "*.png", "-printf", "%f\\n"], (c, out) => {
                const t = {}
                for (const n of (out ?? "").split("\n")) if (n) t[n] = true
                thumbs = t
                Jobs.run(["find", dir, "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
                          "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", ")"], (code, list) => {
                    items = (list ?? "").split("\n").filter(l => l !== "").sort()
                        .map(p => ({ path: p, name: p.split("/").pop(), relDir: relDirOf(p) }))
                    scanned = true
                    _scanning = false
                    setStatus("", "info")
                })
            })
        })
    }

    // djb2 hash → stable cache file name per source path (a rename / move
    // makes a new one instead of serving a stale image)
    function hashPath(p) {
        let h = 5381
        for (let i = 0; i < p.length; i++) h = ((h << 5) + h + p.charCodeAt(i)) | 0
        return (h >>> 0).toString(16)
    }
    function thumbFor(path) { return thumbDir + "/" + hashPath(path) + ".png" }
    function hasThumb(path) { return thumbs[hashPath(path) + ".png"] === true }
    function thumbSaved(path) { const t = Object.assign({}, thumbs); t[hashPath(path) + ".png"] = true; thumbs = t }

    function openFolder() { FileManager.open(dir) }

    function apply(path) {
        if (applyProc.running) return
        pickedPath = path
        setStatus("Applying…", "info")
        // light / dark from the wallpaper (Settings → Theme): decided before wal runs
        Theme.prepareMode(path, m => { applyProc.newMode = m; applyProc.running = true })
    }

    // Kills the whole wallpaper command (bash + magick / wal / awww / …). It
    // runs under `setsid`, so its pid is its process group id and
    // `kill -- -pid` takes every child with it; SIGKILL if something ignores SIGTERM.
    function stop() {
        if (!applyProc.running || !applyProc.processId) return
        applyProc.stopped = true
        Jobs.run(["kill", "-TERM", "--", "-" + applyProc.processId], () => {})
        forceKill.restart()
    }

    Process {
        id: applyProc
        property string newMode: ""        // Theme.prepareMode: the apps switch after the wallpaper is set
        property bool stopped: false
        // setsid → own process group (stop()); the paths are $1 $2 $3, never part of the script
        command: ["setsid", "bash", "-c", 'cp -- "$1" "$2" && bash "$3"', "bash", root.pickedPath, root.outputPath, root.scriptPath]
        onStarted: stopped = false
        onExited: code => {
            forceKill.stop()
            if (code !== 0 || stopped) { if (newMode !== "") Theme.writeModeFile(Theme.mode) }
            if (stopped) root.setStatus("■  stopped", "warn")
            else if (code === 0) {
                root.setStatus("✔  " + root.pickedPath.split("/").pop(), "ok")
                if (newMode !== "") Theme.setMode(newMode, { noWal: true })
            }
            else root.setStatus("✖  failed (code " + code + ")", "error")
        }
    }
    Timer {
        id: forceKill
        interval: 1500
        onTriggered: if (applyProc.running && applyProc.processId)
                         Jobs.run(["kill", "-KILL", "--", "-" + applyProc.processId], () => {})
    }
}
