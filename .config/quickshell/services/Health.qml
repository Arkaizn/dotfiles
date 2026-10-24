pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// Health check (settings app → Maintenance → Health): is everything the shell
// relies on there and working? Each check gives a status, details and a fix.
//
//   results: [{ id, group, title, status: "ok" | "warn" | "error" | "running",
//               detail, fix }]
//   run()            all checks (again)
//   runOne(id)       one check
//   qs ipc call health run      → runs, returns "N ok, N warnings, N errors"
//   qs ipc call health summary  → the last result as text
//
// Startup check (Settings.health.startupCheck, default on): 20 s after the
// shell starts, a notification if something is an *error* (warnings stay quiet).
Singleton {
    id: root

    property var results: []
    property bool running: false
    property real lastRun: 0
    // set by the polkit dialog (modules/polkit) when its agent registers
    property bool polkitAgent: false
    // set by the settings app: () → [{ message }], the current settings checked
    // like an import (would an export of them import again?)
    property var exportCheck: null

    readonly property int errors: results.filter(r => r.status === "error").length
    readonly property int warnings: results.filter(r => r.status === "warn").length

    readonly property string home: Quickshell.env("HOME")

    // programs: required for the shell itself vs. used by one feature
    readonly property var required: [
        { bin: "qs", why: "the shell" }, { bin: "nmcli", why: "network page, Wi-Fi" },
        { bin: "wl-copy", why: "copy buttons, clipboard" }, { bin: "wl-paste", why: "clipboard history" },
        { bin: "cliphist", why: "clipboard history" }, { bin: "jq", why: "focusing windows" },
        { bin: "zenity", why: "file pickers" }, { bin: "magick", why: "wallpapers, profile picture" },
        { bin: "wal", why: "pywal colors" }, { bin: "lua", why: "reading Hyprland's config" },
        { bin: "python3", why: "calendar sync" }, { bin: "checkupdates", why: "update counter" },
        { bin: "notify-send", why: "notifications from scripts" }, { bin: "secret-tool", why: "calendar / connection passwords" },
        { bin: "pkexec", why: "hosts file" }, { bin: "kitty", why: "terminal actions" }, { bin: "git", why: "dotfiles page" }
    ]
    readonly property var optional: [
        { bin: "grim", why: "screenshots" }, { bin: "slurp", why: "region screenshots" }, { bin: "satty", why: "screenshot editing" },
        { bin: "wf-recorder", why: "screen recording" }, { bin: "powerprofilesctl", why: "power profiles" },
        { bin: "traceroute", why: "network diagnostics" }, { bin: "speedtest-cli", why: "speed test" },
        { bin: "qalc", why: "launcher calculator" }, { bin: "shellcheck", why: "checking the shell's scripts" },
        { bin: "keepassxc", why: "password manager (clipboard protection test)" }, { bin: "xfreerdp3", why: "RDP connections" },
        { bin: "vncviewer", why: "VNC connections" }, { bin: "nc", why: "connection reachability" }, { bin: "tesseract", why: "OCR" }, { bin: "gum", why: "dotfiles scripts" },
        { bin: "yay", why: "AUR updates" }, { bin: "sensors", why: "CPU temperature" },
        { bin: "gdu", why: "disk usage page" }, { bin: "smartctl", why: "disk health page" },
        { bin: "reflector", why: "mirrors page" }, { bin: "paccache", why: "cleanup page (package cache)" }
    ]

    function set(id, patch) {
        results = results.map(r => r.id === id ? Object.assign({}, r, patch) : r)
    }

    function checks() {
        const c = [
            { id: "bins", group: "Programs", title: "Required programs" },
            { id: "optbins", group: "Programs", title: "Optional programs" },
            { id: "polkit", group: "Services", title: "Polkit agent" },
            { id: "keyring", group: "Services", title: "Keyring (Secret Service)" },
            { id: "cliphist", group: "Services", title: "Clipboard watcher" },
            { id: "python", group: "Python", title: "Python modules (calendar)" },
            { id: "settings", group: "Config", title: "settings.json" },
            { id: "colors", group: "Config", title: "pywal colors" },
            { id: "files", group: "Config", title: "Files the config uses" }
        ]
        if (Compositor.isNiri || Files.read(NiriSettings.mainConfig) !== "") {
            c.push({ id: "niri", group: "Compositor", title: "niri config (niri validate)" })
            c.push({ id: "includes", group: "Compositor", title: "niri includes" })
        }
        if (HyprSettings.available) c.push({ id: "hypr", group: "Compositor", title: "Hyprland config (--verify-config)" })
        // only where the login screen is installed (greeter/install.sh)
        if (Files.read("/usr/local/share/quickshell-greeter/shell/VERSION") !== "")
            c.push({ id: "greeter", group: "Config", title: "Login screen (greeter)" })
        return c
    }

    function run() {
        running = true
        lastRun = Date.now()
        results = checks().map(c => Object.assign({ status: "running", detail: "", fix: "" }, c))
        for (const r of results) runOne(r.id)
    }

    function runOne(id) {
        set(id, { status: "running" })
        const done = (status, detail, fix) => {
            set(id, { status: status, detail: detail ?? "", fix: fix ?? "" })
            if (results.every(r => r.status !== "running")) { running = false; finished() }
        }
        switch (id) {
        case "bins":
        case "optbins": {
            const list = id === "bins" ? required : optional
            Jobs.which(list.map(x => x.bin), have => {
                const missing = list.filter(x => !have[x.bin])
                if (missing.length === 0) return done("ok", list.length + " found")
                const pk = missing.map(x => Jobs.packages[x.bin] ?? x.bin)
                const repo = pk.filter(p => !p.includes("(AUR)")), aur = pk.filter(p => p.includes("(AUR)")).map(p => p.replace(" (AUR)", ""))
                done(id === "bins" ? "error" : "warn",
                     missing.map(x => x.bin + " (" + x.why + ")").join(", "),
                     [repo.length ? "sudo pacman -S " + repo.join(" ") : "", aur.length ? "yay -S " + aur.join(" ") : ""].filter(x => x).join("   ·   "))
            })
            break
        }
        case "polkit":
            if (polkitAgent) done("ok", "the shell's agent is registered")
            else done("error", "no polkit agent: password prompts (hosts file, global DNS, apps) fail silently",
                      "the shell registers one (modules/polkit): restart it, or check that no other agent blocks it")
            break
        case "keyring":
            Jobs.run(["busctl", "--user", "status", "org.freedesktop.secrets"], code =>
                code === 0 ? done("ok", "org.freedesktop.secrets is available")
                           : done("error", "no Secret Service on the session bus (calendar / connection passwords can't be stored)",
                                  "sudo pacman -S gnome-keyring"))
            break
        case "cliphist":
            Jobs.run(Clipboard.watcherPids, (code, out) =>
                out.trim() !== "" ? done("ok", "wl-paste --watch cliphist store is running")
                           : done("warn", "nothing feeds the clipboard history", "start it at login: wl-paste --watch cliphist store"))
            break
        case "python":
            Jobs.run(["python3", "-c", "import dateutil"], (code, out, err) =>
                code === 0 ? done("ok", "dateutil")
                           : done("error", "python3 can't import dateutil (calendar sync fails)", "sudo pacman -S python-dateutil"))
            break
        case "settings": {
            const text = Files.read(Settings.path)
            if (text === "") return done("ok", "no settings.json yet (all defaults)")
            try { JsonCheck.parse(text) }
            catch (e) {
                return done("error", e.line !== undefined ? "line " + e.line + ", column " + e.col + ": " + e.message : String(e),
                            "fix the file, or restore it from an export (it was not loaded; defaults are used)")
            }
            const errs = exportCheck ? exportCheck() : []
            if (errs.length > 0)
                return done("warn", "an export of these settings wouldn't import again: " + errs.slice(0, 4).map(e => e.message).join("; ")
                                    + (errs.length > 4 ? " (+" + (errs.length - 4) + " more)" : ""),
                            "a setting the import check doesn't know: add it to modules/settings/SettingsTransfer.qml")
            done("ok", "valid, version " + Settings.version + (exportCheck ? ", export / import checked" : ""))
            break
        }
        case "colors": {
            const p = home + "/.cache/wal/colors.json"
            const text = Files.read(p)
            if (text === "") return done("warn", "no " + p + " (default colors are used)", "pick a wallpaper (launcher → wallpapers) or run wal -i <image>")
            try { const j = JSON.parse(text); done(j.colors?.color6 ? "ok" : "warn", j.colors?.color6 ? "16 colors" : "colors.json has no colors") }
            catch (e) { done("error", "colors.json isn't valid JSON", "run wal again") }
            break
        }
        case "files": {
            const files = [home + "/.config/quickshell/scripts/lock.sh", home + "/.config/quickshell/scripts/set_wallpaper.sh",
                           home + "/.config/quickshell/scripts/hypr-binds.lua", home + "/Pictures/Wallpapers"]
            Jobs.run(["sh", "-c", 'for f in "$@"; do [ -e "$f" ] || echo "$f"; done', "sh"].concat(files), (code, out) => {
                const miss = out.split("\n").filter(x => x)
                miss.length === 0 ? done("ok", files.length + " found")
                                  : done("warn", "missing: " + miss.map(f => f.replace(home, "~")).join(", "), "restore them from the dotfiles repo")
            })
            break
        }
        case "niri":
            Jobs.run(["niri", "validate"], (code, out, err) => {
                if (code === 0) return done("ok", "config is valid")
                const msg = (out + "\n" + err).replace(/\x1b\[[0-9;]*m/g, "").split("\n").filter(l => l.trim() && !/ (DEBUG|INFO) /.test(l)).slice(-4).join("\n")
                done("error", msg || "niri validate failed", "fix " + NiriSettings.mainConfig.replace(home, "~") + " (niri keeps the last valid config)")
            })
            break
        case "includes": {
            // non-optional includes of config.kdl must exist (niri refuses to load otherwise)
            const text = Files.read(NiriSettings.mainConfig)
            const dir = NiriSettings.configDir
            const paths = []
            for (const l of text.split("\n")) {
                const m = /^\s*include\s+(optional=true\s+)?"([^"]+)"/.exec(l)
                if (m && !m[1]) paths.push(NiriSettings.expand(m[2], dir))
            }
            Jobs.run(["sh", "-c", 'for f in "$@"; do [ -e "$f" ] || echo "$f"; done', "sh"].concat(paths), (code, out) => {
                const miss = out.split("\n").filter(x => x)
                miss.length === 0 ? done("ok", paths.length + " includes, all there")
                                  : done("error", "missing: " + miss.map(f => f.replace(home, "~")).join(", "),
                                         "create the file(s), or write include optional=true \"…\"")
            })
            break
        }
        case "hypr":
            Jobs.run(["Hyprland", "--verify-config", "-c", HyprSettings.mainConfig], (code, out, err) => {
                const res = (out + err).replace(/\x1b\[[0-9;]*m/g, "")
                const after = res.split("Config parsing result:")[1] ?? ""
                if (code === 0) return done("ok", "config ok")
                done("error", after.trim().split("\n").slice(0, 4).join("\n") || "Hyprland --verify-config failed",
                     "fix " + HyprSettings.mainConfig.replace(home, "~"))
            }, { HYPRLAND_NO_SD_VARS: "1", HYPRLAND_NO_SD_NOTIFY: "1" })
            break
        case "greeter": {
            // its code = this config's greeter/, its theme copy written, the font readable for the greeter user
            const installed = Files.read("/usr/local/share/quickshell-greeter/shell/VERSION").trim()
            Jobs.run(["sh", "-c", 'bash "$1/greeter/build.sh" "${XDG_RUNTIME_DIR:-/tmp}/quickshell-greeter-check"; ' +
                      'fc-list -f "%{file}\\n" "$2" | grep -c "^/usr/" || true', "sh", Quickshell.shellDir, Properties.fontFamily], (code, out) => {
                const [built, sysFonts] = out.trim().split("\n")
                const probs = []
                if (built && built !== installed) probs.push("the installed login screen (" + installed + ") is older than greeter/ (" + built + ")")
                if (GreeterSync.status !== "up to date" && GreeterSync.status !== "off") probs.push("theme copy: " + GreeterSync.status)
                if (Number(sysFonts) === 0) probs.push("the font \"" + Properties.fontFamily + "\" isn't installed system-wide (the login screen falls back to another one)")
                probs.length === 0 ? done("ok", "code " + installed + ", theme copy up to date")
                                   : done("warn", probs.join("; ") + " (Settings → Login screen → Install / update, or the command)", "sudo ~/.config/quickshell/greeter/install.sh")
            })
            break
        }
        default:
            done("warn", "unknown check")
        }
    }

    signal finished()

    function summary() {
        if (results.length === 0) return "not run yet"
        return results.filter(r => r.status === "ok").length + " ok, " + warnings + " warnings, " + errors + " errors"
            + results.filter(r => r.status !== "ok").map(r => "\n- [" + r.status + "] " + r.title + ": " + r.detail).join("")
    }

    // ── Startup check ───────────────────────────────────────────────────────
    property bool _startup: false
    Timer {
        running: Settings.loaded && (Settings.health.startupCheck ?? true)
        interval: 20000
        onTriggered: { root._startup = true; root.run() }
    }
    onFinished: {
        if (!_startup) return
        _startup = false
        if (errors > 0)
            Jobs.run(["notify-send", "--app-name=Health check", "--icon=dialog-warning",
                      "Health check: " + errors + (errors === 1 ? " problem" : " problems"),
                      results.filter(r => r.status === "error").map(r => r.title).join(", ") + "\nSettings → Maintenance → Health"])
    }

    IpcHandler {
        target: "health"
        function run(): string { root.run(); return "started (" + root.checks().length + " checks)" }
        function summary(): string { return root.summary() }
    }
}
