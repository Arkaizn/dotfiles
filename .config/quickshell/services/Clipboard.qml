pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history (cliphist) settings for the settings app (Apps → Clipboard):
// watcher status / pause, history size, wipe, and whether passwords stay out.
//
// Passwords: KeePassXC (and other password managers) mark what they copy with
// x-kde-passwordManagerHint=secret; wl-paste (≥ 2.2) then runs the store
// command with CLIPBOARD_STATE=sensitive and cliphist (≥ 0.6) skips it.
//
// cliphist reads ~/.config/cliphist/config on every store, so size changes
// apply to the next copy.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/cliphist/config"
    readonly property var watcherCmd: ["wl-paste", "--watch", "cliphist", "store"]
    // pids of exactly `wl-paste --watch cliphist store` (pgrep -f would also
    // match any process that merely mentions that text, e.g. a shell or editor)
    readonly property var watcherPids: ["sh", "-c",
        'for p in $(pgrep -x wl-paste); do c=$(tr "\\0" " " < "/proc/$p/cmdline"); case $c in "wl-paste --watch cliphist store "|*"/wl-paste --watch cliphist store ") echo "$p" ;; esac; done']

    property bool watching: false
    property int count: 0
    property var options: ({})             // from `cliphist version` (current effective values)
    property string cliphistVersion: ""
    property string wlVersion: ""
    property bool loaded: false

    // passwords skipped? (version check, behaviour tested with KeePassXC's hint)
    readonly property bool protectedPasswords: newer(cliphistVersion, "0.6.0") && newer(wlVersion, "2.2.0")
    function newer(v, min) {
        const a = String(v).split(".").map(Number), b = min.split(".").map(Number)
        if (a.length < 2 || a.some(isNaN)) return false
        for (let i = 0; i < 3; i++) { if ((a[i] ?? 0) !== b[i]) return (a[i] ?? 0) > b[i] }
        return true
    }

    function refresh() {
        Jobs.run(watcherPids, (code, out) => watching = out.trim() !== "")
        Jobs.run(["cliphist", "list"], (code, out) => count = code === 0 ? out.split("\n").filter(l => l).length : 0)
        // (cliphist prints this on stderr)
        Jobs.run(["cliphist", "version"], (code, out, err) => {
            const o = {}
            for (const l of (out + "\n" + err).split("\n")) { const m = /^(\S+)\t(.*)$/.exec(l); if (m) o[m[1]] = m[2] }
            cliphistVersion = o.version ?? ""
            options = o
            loaded = true
        })
        Jobs.run(["wl-paste", "--version"], (code, out) => wlVersion = (/wl-clipboard (\S+)/.exec(out)?.[1]) ?? "")
    }

    // pause = stop the watcher until resumed (or the next login)
    function pause() {
        Jobs.run(watcherPids, (code, out) => {
            const pids = out.split("\n").filter(p => /^\d+$/.test(p))
            if (pids.length === 0) return refresh()
            Jobs.run(["kill", "--"].concat(pids), () => later(refresh))
        })
    }
    function resume() { Quickshell.execDetached(watcherCmd); later(refresh) }

    function wipe(cb) { Jobs.run(["cliphist", "wipe"], code => { refresh(); if (cb) cb(code === 0) }) }

    // write max-items / min-store-length (keeps other lines of the config)
    function setOption(key, value, cb) {
        if (!["max-items", "min-store-length"].includes(key)) return
        const n = Math.round(Number(value))
        if (!(n >= 0 && n <= 100000) || (key === "max-items" && n < 1)) return cb && cb(false)
        const text = NiriSettings.readFile(configFile)
        const lines = text.split("\n").filter(l => l.trim() !== "" && !l.trim().startsWith(key + " "))
        lines.push(key + " " + n)
        Jobs.runInput(["sh", "-c", 'mkdir -p -- "$(dirname -- "$1")" && cat > "$1"', "sh", configFile], lines.join("\n") + "\n", code => {
            refresh()
            if (cb) cb(code === 0)
        })
    }

    Component { id: laterTimer; Timer { property var fn; interval: 400; running: true; onTriggered: { fn(); destroy() } } }
    function later(fn) { laterTimer.createObject(root, { fn: fn }) }
}
