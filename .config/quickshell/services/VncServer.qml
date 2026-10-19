pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VNC server for this device (wayvnc), so you can connect to it from another
// computer (settings app → Apps → Connections → This device).
//
// Login: your system account, checked by PAM (/etc/pam.d/wayvnc), over an
// encrypted connection (RSA-AES; the key is made once with ssh-keygen).
// Viewers need RSA-AES support (TigerVNC 1.13+, RealVNC). Its own config, key,
// control socket and log live in $XDG_STATE_HOME/quickshell/wayvnc (your
// ~/.config/wayvnc is left alone). Runs detached: survives a shell restart.
// A notification when someone connects.
//
// Settings.connections.server: { port: 5900, output: "" (= focused monitor),
//                                viewOnly: false, autostart: false }
//   qs ipc call vncServer start | stop | status
Singleton {
    id: root

    readonly property var cfg: Settings.connections.server ?? ({})
    readonly property int port: cfg.port ?? 5900
    readonly property string output: cfg.output ?? ""
    readonly property bool viewOnly: cfg.viewOnly ?? false
    readonly property bool autostart: cfg.autostart ?? false
    function setOpt(k, v) {
        const m = Object.assign({}, cfg)
        m[k] = v
        Settings.set("connections", "server", m)
    }

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/wayvnc"
    readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-wayvnc.sock"

    property bool running: false
    property bool starting: false
    property var clients: []                // [{ id, address, username }]
    property string error: ""
    property string lanAddress: ""          // e.g. 192.168.0.177
    property string lanNet: ""              // e.g. 192.168.0.0/24 (for the firewall rule)

    // ── start / stop ────────────────────────────────────────────────────────
    function start() {
        if (running || starting) return
        error = ""
        starting = true
        Jobs.which(["wayvnc", "wayvncctl", "ssh-keygen"], have => {
            const miss = ["wayvnc", "wayvncctl", "ssh-keygen"].filter(b => !have[b])
            if (miss.length > 0) { starting = false; error = "missing: " + miss.map(b => Jobs.installHint(b)).join(", "); return }
            // fixed script; paths and options passed as data
            Jobs.run(["sh", "-c",
                'dir=$1; port=$2; mkdir -p "$dir" && chmod 700 "$dir" || exit 1\n'
              + '[ -s "$dir/rsa_key.pem" ] || ssh-keygen -q -m pem -t rsa -b 3072 -N "" -f "$dir/rsa_key.pem" || exit 1\n'
              + 'umask 077\n'
              + 'printf "address=0.0.0.0\\nport=%s\\nenable_auth=true\\nenable_pam=true\\nrsa_private_key_file=%s\\n" "$port" "$dir/rsa_key.pem" > "$dir/config"',
                "sh", dir, String(port)], code => {
                if (code !== 0) { starting = false; error = "couldn't write the config / key in " + dir; return }
                launch()
            })
        })
    }

    Component { id: detachedProc; Process {} }
    function launch() {
        const args = ["-C", dir + "/config", "-S", socket, "-f", "30", "-r"]
        if (output !== "") args.push("-o", output)
        if (viewOnly) args.push("-d")
        const p = detachedProc.createObject(root, { command: ["sh", "-c",
            'log=$1; shift; rm -f "$log.old"; [ -f "$log" ] && mv "$log" "$log.old"; exec wayvnc "$@" >"$log" 2>&1',
            "sh", dir + "/wayvnc.log"].concat(args) })
        p.startDetached()
        p.destroy()
        later(1200, () => { starting = false; refresh(true) })
    }

    function stop() {
        Jobs.run(["wayvncctl", "-S", socket, "wayvnc-exit"], () => later(500, () => refresh()))
    }
    function restart() { if (!running) return start(); Jobs.run(["wayvncctl", "-S", socket, "wayvnc-exit"], () => later(700, start)) }

    function disconnect(id) { Jobs.run(["wayvncctl", "-S", socket, "client-disconnect", "--id=" + id], () => refresh()) }

    // ── state ───────────────────────────────────────────────────────────────
    // afterStart: a failed start shows the end of wayvnc's log
    function refresh(afterStart) {
        Jobs.run(["wayvncctl", "-S", socket, "-j", "client-list"], (code, out) => {
            running = code === 0
            if (running) {
                try { clients = (JSON.parse(out) ?? []).map(c => ({ id: c.id, address: c.address ?? c.hostname ?? "", username: c.username ?? "" })) }
                catch (e) { clients = [] }
            } else {
                clients = []
                if (afterStart) Jobs.run(["tail", "-n", "3", dir + "/wayvnc.log"], (c, log) => error = log.trim() || "wayvnc didn't start")
            }
        })
        Jobs.run(["sh", "-c", 'dev=$(ip -o -4 route show default | awk \'{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i+1); exit } }\'); [ -n "$dev" ] && ip -o -4 addr show dev "$dev" scope global | awk \'{ print $4; exit }\''],
                 (c, out) => {
            const m = /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)/.exec(out.trim())
            if (!m) { lanAddress = ""; lanNet = ""; return }
            lanAddress = m.slice(1, 5).join(".")
            const bits = Number(m[5])
            const ip = m.slice(1, 5).reduce((a, x) => a * 256 + Number(x), 0)
            const net = bits === 0 ? 0 : Math.floor(ip / Math.pow(2, 32 - bits)) * Math.pow(2, 32 - bits)
            lanNet = [24, 16, 8, 0].map(s => Math.floor(net / Math.pow(2, s)) % 256).join(".") + "/" + bits
        })
    }

    // while it runs: connect / disconnect events → notification + client list
    Process {
        id: events
        running: root.running
        command: ["wayvncctl", "-S", root.socket, "-j", "-r", "event-receive"]
        stdout: SplitParser {
            onRead: line => {
                if (/client-connected/.test(line)) {
                    let who = ""
                    try { const p = JSON.parse(line).params ?? {}; who = [p.username, p.address].filter(x => x).join(" from ") } catch (e) {}
                    Jobs.run(["notify-send", "-a", "VNC server", "-u", "critical", "-i", "preferences-desktop-remote-desktop",
                              "Someone connected via VNC", (who || "a client") + " is now viewing" + (root.viewOnly ? "" : " and controlling") + " this screen"])
                }
                root.refresh()
            }
        }
    }

    // slow check while it runs (it can be stopped from elsewhere)
    Timer { running: root.running; interval: 10000; repeat: true; onTriggered: root.refresh() }

    Component {
        id: timerComp
        Timer { property var fn; onTriggered: { fn(); destroy() } }
    }
    function later(ms, fn) { timerComp.createObject(root, { interval: ms, fn: fn, running: true }) }

    Component.onCompleted: {
        refresh()
        if (autostart) later(3000, () => { if (!running) start() })
    }

    IpcHandler {
        target: "vncServer"
        function start(): void { root.start() }
        function stop(): void { root.stop() }
        function status(): string {
            return root.running ? "running on " + (root.lanAddress || "0.0.0.0") + ":" + root.port + ", " + root.clients.length + " connected" : "stopped"
        }
    }
}
