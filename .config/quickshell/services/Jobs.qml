pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Shared command runner for the settings app, tools and services.
//
// Commands are argument arrays only (never `sh -c` with user input).
//
//   Jobs.run(argv, cb)                    one-shot: cb(code, stdout, stderr)
//   Jobs.runInput(argv, input, cb)        same, `input` written to stdin (then closed);
//                                         for secrets (secret-tool store), never argv
//   Jobs.start(id, argv, opts)            long-running job, output streamed:
//       opts: { timeout (ms), maxLines (default 400), store (false = don't keep lines), env: {…}, cwd,
//               onLine(text, isErr), onExit(code) }
//   Jobs.cancel(id)                       stop it (SIGTERM via running = false)
//   Jobs.state(id)                        { running, lines: [{ text, err }], code, cancelled, timedOut, missing }
//   Jobs.which(bins, cb)                  cb({ bin: true/false }) — which tools are installed
//   Jobs.detached(argv, env, cwd)         start a program that outlives the shell
//   Jobs.later(ms, fn)                    run fn once after ms
//
// A job whose program isn't installed ends with `missing: "<program>"`, so the
// UI can show "install …" instead of an empty failure.
Singleton {
    id: root

    // id → state (reassigned on change so bindings update)
    property var jobs: ({})
    signal lineAdded(string id, string text, bool isErr)
    signal jobFinished(string id, int code)

    // package that provides a program (for "install …" hints)
    readonly property var packages: ({
        "qs": "quickshell", "niri": "niri", "nmcli": "networkmanager", "cliphist": "cliphist",
        "wl-copy": "wl-clipboard", "wl-paste": "wl-clipboard", "grim": "grim", "slurp": "slurp", "satty": "satty",
        "jq": "jq", "zenity": "zenity", "magick": "imagemagick", "wal": "python-pywal16-git (AUR)", "lua": "lua",
        "python3": "python", "checkupdates": "pacman-contrib", "git": "git", "notify-send": "libnotify",
        "secret-tool": "libsecret", "pkexec": "polkit", "gum": "gum", "tesseract": "tesseract", "kitty": "kitty",
        "xfreerdp3": "freerdp", "vncviewer": "tigervnc", "ssh": "openssh", "ssh-add": "openssh",
        "ssh-keygen": "openssh", "gpg": "gnupg", "qalc": "libqalculate", "wf-recorder": "wf-recorder",
        "powerprofilesctl": "power-profiles-daemon", "traceroute": "traceroute", "speedtest-cli": "speedtest-cli",
        "shellcheck": "shellcheck", "keepassxc": "keepassxc", "nvidia-smi": "nvidia-utils", "sensors": "lm_sensors",
        "nc": "openbsd-netcat", "ping": "iputils", "curl": "curl", "xdg-mime": "xdg-utils",
        "xdg-settings": "xdg-utils", "resolvectl": "systemd", "busctl": "systemd", "pgrep": "procps-ng",
        "yay": "yay (AUR)", "Hyprland": "hyprland", "wpctl": "wireplumber", "bluetoothctl": "bluez-utils",
        "rsync": "rsync", "gdu": "gdu", "smartctl": "smartmontools", "reflector": "reflector", "paccache": "pacman-contrib", "pw-play": "pipewire", "pactl": "libpulse"
    })
    function installHint(bin) {
        const p = packages[bin] ?? bin
        return p.includes("(AUR)") ? "install " + p.replace(" (AUR)", "") + " from the AUR" : "sudo pacman -S " + p
    }

    // ── One-shot ────────────────────────────────────────────────────────────
    Component {
        id: oneShot
        Process {
            property var callback
            property string input: ""
            property bool feed: false
            stdinEnabled: feed
            onStarted: if (feed) { write(input); input = ""; feed = false }
            stdout: StdioCollector { id: o }
            stderr: StdioCollector { id: e }
            onExited: code => {
                const cb = callback, out = o.text, err = e.text
                destroy()
                if (cb) cb(code, out, err)
            }
        }
    }

    function run(argv, cb, env) {
        const p = oneShot.createObject(root, { command: argv, callback: cb })
        if (env) p.environment = env
        p.running = true
        return p
    }

    function runInput(argv, input, cb) {
        const p = oneShot.createObject(root, { command: argv, callback: cb, input: input, feed: true })
        p.running = true
        return p
    }

    // ── Detached: keeps running when the shell restarts ─────────────────────
    // (Quickshell.execDetached can't take a JS object for env / cwd on 0.3.2,
    // so a Process is made just to start it detached)
    Component { id: detachedProc; Process {} }

    function detached(argv, env, cwd) {
        const p = detachedProc.createObject(root, { command: argv })
        if (env) p.environment = env
        if (cwd) p.workingDirectory = cwd
        p.startDetached()
        p.destroy()
    }

    // ── fn() after `ms` milliseconds, once ──────────────────────────────────
    Component {
        id: laterTimer
        Timer { property var fn; onTriggered: { try { fn() } finally { destroy() } } }
    }

    function later(ms, fn) { laterTimer.createObject(root, { interval: ms, fn: fn, running: true }) }

    // which of `bins` are installed: cb({ bin: bool })
    function which(bins, cb) {
        run(["sh", "-c", 'for b in "$@"; do if command -v -- "$b" >/dev/null 2>&1; then echo "1 $b"; else echo "0 $b"; fi; done', "sh"].concat(bins),
            (code, out) => {
                const r = {}
                for (const l of out.split("\n")) { const m = /^([01]) (.+)$/.exec(l); if (m) r[m[2]] = m[1] === "1" }
                cb(r)
            })
    }

    // ── Long-running, streamed ──────────────────────────────────────────────
    Component {
        id: streamed
        Process {
            id: proc
            property string jobId
            property var opts: ({})
            property bool cancelled: false
            property bool timedOut: false
            stdout: SplitParser { onRead: line => root._line(proc.jobId, line, false) }
            stderr: SplitParser { onRead: line => root._line(proc.jobId, line, true) }
            onExited: code => root._exit(proc, code)
            property Timer timer: Timer {
                interval: proc.opts.timeout ?? 0
                running: proc.running && (proc.opts.timeout ?? 0) > 0
                onTriggered: { proc.timedOut = true; proc.running = false }
            }
        }
    }

    property var _procs: ({})

    function state(id) { return jobs[id] ?? { running: false, lines: [], code: -1 } }
    function isRunning(id) { return jobs[id]?.running ?? false }

    function start(id, argv, opts) {
        cancel(id)
        opts = opts ?? {}
        const st = { running: true, lines: [], code: -1, cancelled: false, timedOut: false, missing: "", started: Date.now() }
        _set(id, st)
        // a missing program gives exit 127 from the shell, but Process runs it
        // directly: check first so the UI can say what to install
        which([argv[0]], r => {
            if (!jobs[id] || !jobs[id].running || jobs[id].started !== st.started) return
            if (!r[argv[0]]) {
                _set(id, Object.assign({}, jobs[id], { running: false, code: 127, missing: argv[0] }))
                if (opts.onExit) opts.onExit(127)
                jobFinished(id, 127)
                return
            }
            const p = streamed.createObject(root, { jobId: id, opts: opts, command: argv })
            if (opts.env) p.environment = opts.env
            if (opts.cwd) p.workingDirectory = opts.cwd
            const m = Object.assign({}, _procs); m[id] = p; _procs = m
            p.running = true
        })
    }

    function cancel(id) {
        const p = _procs[id]
        if (p && p.running) { p.cancelled = true; p.running = false }
    }

    function clear(id) {
        if (isRunning(id)) return
        const j = Object.assign({}, jobs); delete j[id]; jobs = j
    }

    function _set(id, st) { const j = Object.assign({}, jobs); j[id] = st; jobs = j }

    function _line(id, text, isErr) {
        const st = jobs[id]
        if (!st) return
        // store: false = only hand lines to onLine (fast streams nobody reads back)
        if (_procs[id]?.opts?.store === false) {
            const cb0 = _procs[id].opts.onLine
            if (cb0) cb0(text, isErr)
            return
        }
        const max = _procs[id]?.opts?.maxLines ?? 400
        const lines = st.lines.concat([{ text: text, err: isErr }])
        if (lines.length > max) lines.splice(0, lines.length - max)
        _set(id, Object.assign({}, st, { lines: lines }))
        const cb = _procs[id]?.opts?.onLine
        if (cb) cb(text, isErr)
        lineAdded(id, text, isErr)
    }

    function _exit(p, code) {
        const id = p.jobId
        if (_procs[id] !== p) { p.destroy(); return }   // replaced by a newer start()
        _set(id, Object.assign({}, jobs[id] ?? {}, { running: false, code: code, cancelled: p.cancelled, timedOut: p.timedOut }))
        const cb = p.opts.onExit
        const m = Object.assign({}, _procs); delete m[id]; _procs = m
        p.destroy()
        if (cb) cb(code)
        jobFinished(id, code)
    }
}
