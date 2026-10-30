pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib

// Keeps the login screen's theme folder (/var/lib/quickshell-greeter/theme,
// created by greeter/install.sh) up to date: the greeter runs as its own user
// and can't read your home. 2 s after the colors, the wallpaper, the monitors,
// the keyboard layout or a setting it shows changed (and once at start),
// scripts/greeter-theme.sh writes only what changed. Off with Settings →
// Login screen → "Keep the login screen's theme up to date".
//
// What goes there (nothing else from your home): pywal colors, the wallpaper
// (scaled), your picture (only if it's shown), these settings groups:
// properties, icons, lockscreen, greeter, profile.name (only if shown); meta
// { owner, yubikey, face }; outputs.txt / input.txt for the greeter's niri.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("QS_GREETER_THEME_DIR") || "/var/lib/quickshell-greeter/theme"
    readonly property string home: Quickshell.env("HOME")
    readonly property string wallpaper: home + "/.local/share/backgrounds/pywallpaper.png"
    readonly property string colorsFile: home + "/.cache/wal/colors.json"
    readonly property string script: Quickshell.shellDir + "/scripts/greeter-theme.sh"
    readonly property var show: LockItems.resolveGreeter(Settings.lockscreen, Settings.greeter)

    // "off", "not installed", "updating", "up to date", "failed: …"
    property string status: "updating"
    property string lastSync: ""            // HH:mm of the last successful run
    property string installedVersion: ""    // VERSION of the installed greeter code
    readonly property bool installed: status !== "not installed"

    // ── what the login screen gets ──
    function bundle() {
        const shown = show.avatar
        const settings = {
            version: Settings.version,
            properties: Settings.properties,
            icons: Settings.icons,
            lockscreen: Settings.lockscreen,
            greeter: Settings.greeter,
            profile: shown && Settings.profile.name ? { name: Settings.profile.name } : {}
        }
        // yubikey: kept for a greeter installed before yubikeyMode ("none" | "otp" | "fido2")
        const meta = { owner: Quickshell.env("USER") ?? "", yubikey: Yubikey.present, yubikeyMode: Yubikey.mode, face: shown }
        return { settings: settings, meta: meta, outputs: outputsText(), input: inputText() }
    }

    // one line per monitor: ident \t mode \t scale \t transform \t x \t y \t on|off
    // (saved on the Monitors page, plus connected ones that aren't saved)
    function outputsText() {
        const lines = []
        const seen = {}
        const add = (id, c) => {
            if (seen[id] || !c.mode) return
            seen[id] = true
            lines.push([id, c.mode, c.scale ?? 1, c.transform ?? "normal", Math.round(c.x ?? 0), Math.round(c.y ?? 0),
                        c.enabled === false ? "off" : "on"].join("\t"))
        }
        for (const id of Object.keys(Settings.monitors ?? {}))
            if (!id.startsWith("Unknown Unknown")) add(id, Settings.monitors[id])
        for (const o of Monitors.outputs) {
            const unique = Monitors.outputs.filter(x => x.ident === o.ident).length === 1
            add(unique && !o.ident.startsWith("Unknown Unknown") ? o.ident : o.name,
                { mode: Monitors.modeString(o.width, o.height, o.refresh), scale: o.scale, transform: o.transform,
                  x: o.x, y: o.y, enabled: o.enabled })
        }
        return lines.join("\n") + "\n"
    }
    // the biggest monitor (pixels), for scaling the wallpaper
    function maxSize() {
        let w = 1920, h = 1080
        for (const o of Monitors.outputs) if (o.width * o.height > w * h) { w = o.width; h = o.height }
        return w + "x" + h
    }

    // key=value lines from your niri config (input.kdl + the settings app's overrides)
    function inputText() {
        const out = {}
        NiriSettings.parseInto(NiriSettings.mainConfig, out, { order: 0 }, 0)
        const arg = p => out[p]?.args?.[0]
        const flag = p => out[p] ? (out[p].args[0] === undefined || out[p].args[0] === "true" ? "yes" : "no") : "no"
        const kv = {
            layout: NiriSettings.value("kbLayout"),
            variant: arg("input/keyboard/xkb/variant") ?? "",
            options: arg("input/keyboard/xkb/options") ?? "",
            numlock: NiriSettings.value("numlock") ? "yes" : "no",
            tap: flag("input/touchpad/tap"),
            naturalScroll: flag("input/touchpad/natural-scroll")
        }
        return Object.keys(kv).map(k => k + "=" + kv[k]).join("\n") + "\n"
    }

    // ── running it ──
    function sync() {
        if (!show.sync) { status = "off"; return }
        if (Jobs.isRunning("greeter-theme")) { syncTimer.restart(); return }
        status = "updating"
        const face = show.avatar ? home + "/.face" : "-"
        Jobs.runInput(["bash", script, dir, wallpaper, face, colorsFile, maxSize()], JSON.stringify(bundle()), (code, out, err) => {
            if (code === 0) { status = "up to date"; lastSync = Qt.formatTime(new Date(), "HH:mm") }
            else if (code === 3) status = "not installed"
            else { status = "failed: " + (err.trim().split("\n").pop() || "exit " + code); console.warn("greeter-theme.sh:", err) }
            readVersion()
        })
    }
    function readVersion() { installedVersion = Files.read("/usr/local/share/quickshell-greeter/shell/VERSION").trim() }

    Timer { id: syncTimer; interval: 2000; onTriggered: root.sync() }
    function changed() { syncTimer.restart() }

    Connections {
        target: Settings
        function onPropertiesChanged() { root.changed() }
        function onIconsChanged() { root.changed() }
        function onLockscreenChanged() { root.changed() }
        function onGreeterChanged() { root.changed() }
        function onProfileChanged() { root.changed() }
        function onMonitorsChanged() { root.changed() }
        function onNiriChanged() { root.changed() }
    }
    Connections { target: Monitors; function onOutputsChanged() { root.changed() } }
    Connections { target: Yubikey; function onPresentChanged() { root.changed() } }
    // a new wallpaper always ends with wal writing colors.json
    FileView { path: root.colorsFile; watchChanges: true; printErrors: false; onFileChanged: root.changed() }

    // once at start, after the rest of the shell is up
    Component.onCompleted: { readVersion(); Jobs.later(8000, () => root.sync()) }
}
