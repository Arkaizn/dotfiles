import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"
// Network diagnostics: connectivity at a glance (NetworkManager's check,
// captive portal login, gateway / internet latency, DNS; parsed by
// services/lib/NetCheck.js), ping, traceroute, port check, speed test
// (speedtest-cli, or curl against speed.cloudflare.com). Every field
// is checked (Valid.js) before anything runs; commands are argument lists;
// each job can be cancelled and is stopped when the page closes.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var jobIds: ["diag-ping", "diag-trace", "diag-port", "diag-speed"]

    // ── connectivity check: on open and on "Check again" ──
    readonly property string checkScript:
        'echo "@@URI $(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager'
        + ' org.freedesktop.NetworkManager ConnectivityCheckUri 2>/dev/null)"\n'
        + 'gw=$(ip -4 route show default 2>/dev/null | awk \'{ print $3; exit }\')\n'
        + 'echo "@@GW $gw"\n'
        + '[ -n "$gw" ] && ping -n -q -c 3 -i 0.3 -W 2 "$gw" 2>&1 | tail -n 2\n'
        + 'echo "@@NET $1"\n'
        + 'ping -n -q -c 3 -i 0.3 -W 2 "$1" 2>&1 | tail -n 2\n'
        + 'echo "@@DNS"\n'
        + 't=$(date +%s%N); if getent ahosts "$2" >/dev/null 2>&1; then echo "ok $(( ($(date +%s%N) - t) / 1000000 ))"; else echo fail; fi\n'
    readonly property string checkHost: "1.1.1.1"
    readonly property string checkName: "archlinux.org"
    property var check: null              // NetCheck.parse result
    property bool checking: false
    function runCheck() {
        if (checking) return
        checking = true
        Network.recheck(() => Jobs.run(["sh", "-c", checkScript, "sh", checkHost, checkName], (code, out) => {
            checking = false
            check = NetCheck.parse(out)
        }))
    }
    readonly property var dnsServers: Network.resolved.reduce((a, r) => a.concat(r.servers), []).filter((s, i, a) => a.indexOf(s) === i)

    // speed test without speedtest-cli: curl against speed.cloudflare.com, same output
    readonly property string speedScript:
        'u=https://speed.cloudflare.com\n'
        + 'echo "Server: speed.cloudflare.com (curl)"\n'
        + 'lat=$(for i in 1 2 3; do curl -s -o /dev/null -w \'%{time_appconnect} %{time_starttransfer}\\n\' "$u/__down?bytes=0"; done'
        + ' | awk \'{ d = $2 - $1; if (min == "" || d < min) min = d } END { if (min != "") printf "%.1f", min * 1000 }\')\n'
        + '[ -n "$lat" ] || { echo "Can\'t reach speed.cloudflare.com" >&2; exit 1; }\n'
        + 'echo "Ping: $lat ms"\n'
        + 'r=$(curl -s -o /dev/null --max-time 15 -w \'%{speed_download}\' "$u/__down?bytes=$1") || [ -n "$r" ] || { echo "Download failed" >&2; exit 1; }\n'
        + 'awk -v b="$r" \'BEGIN { printf "Download: %.2f Mbit/s\\n", b * 8 / 1e6 }\'\n'
        + 'r=$(head -c "$2" /dev/zero | curl -s -o /dev/null --max-time 15 -w \'%{speed_upload}\' --data-binary @- "$u/__up") || [ -n "$r" ] || { echo "Upload failed" >&2; exit 1; }\n'
        + 'awk -v b="$r" \'BEGIN { printf "Upload: %.2f Mbit/s\\n", b * 8 / 1e6 }\'\n'
    property bool hasSpeedtestCli: false
    Component.onCompleted: {
        runCheck()
        Jobs.which(["speedtest-cli"], r => page.hasSpeedtestCli = r["speedtest-cli"] === true)
    }
    Component.onDestruction: { for (const id of jobIds) Jobs.cancel(id) }

    property string host: Settings.netTools.lastHost ?? ""
    property string count: "4"
    property string portHost: Settings.netTools.lastPortHost ?? ""
    property string port: Settings.netTools.lastPort ?? "22"
    property var errors: ({})

    function remember(k, v) { Settings.set("netTools", k, v) }

    function run(id) {
        const e = {}
        let argv = null, opts = { timeout: 60000 }
        if (id === "diag-ping" || id === "diag-trace") {
            const h = Valid.host(host); if (h) e.host = h
            if (id === "diag-ping") { const c = Valid.intRange(count, 1, 50); if (c) e.count = c }
            if (Object.keys(e).length === 0) {
                remember("lastHost", host.trim())
                argv = id === "diag-ping" ? ["ping", "-c", count.trim(), "-W", "2", "--", host.trim()]
                                          : ["traceroute", "-n", "-q", "1", "-w", "2", "-m", "30", host.trim()]
                opts.timeout = id === "diag-ping" ? (Number(count) + 5) * 1000 * 2 : 120000
            }
        } else if (id === "diag-port") {
            const h = Valid.host(portHost); if (h) e.portHost = h
            const p = Valid.port(port); if (p) e.port = p
            if (Object.keys(e).length === 0) {
                remember("lastPortHost", portHost.trim()); remember("lastPort", port.trim())
                argv = ["nc", "-z", "-v", "-w", "3", "--", portHost.trim(), port.trim()]
                opts.timeout = 15000
            }
        } else if (id === "diag-speed") {
            argv = hasSpeedtestCli ? ["speedtest-cli", "--simple", "--secure"]
                                   : ["sh", "-c", speedScript, "sh", "25000000", "10000000"]
            opts.timeout = 120000
        }
        errors = e
        if (argv) Jobs.start(id, argv, opts)
    }

    // ── Connectivity ────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Connectivity"
        icon: "󰖟"
        NetRow {
            first: true
            label: !Network.networking ? "Networking is off"
                 : ({ full: "Online", limited: "Limited: no internet", portal: "Captive portal: log in to get online",
                      none: "Offline" })[Network.connectivity] ?? "Not checked"
            desc: page.check?.uri ? "NetworkManager checks " + page.check.uri : "NetworkManager's connectivity check"
            ActionButton {
                visible: Network.connectivity === "portal"
                icon: "󰖟"
                text: "Open login page"
                primary: true
                onClicked: Network.openPortal()
            }
            ActionButton {
                icon: "󰑓"
                text: page.checking ? "Checking…" : "Check again"
                interactive: !page.checking
                onClicked: page.runCheck()
            }
        }
        NetRow {
            label: "Router" + (page.check?.gateway ? " (" + page.check.gateway + ")" : "")
            desc: page.check === null ? "…" : page.check.gateway === "" ? "no default route" : NetCheck.pingText(page.check.gwPing)
        }
        NetRow {
            label: "Internet (" + page.checkHost + ")"
            desc: page.check === null ? "…" : NetCheck.pingText(page.check.netPing)
        }
        NetRow {
            label: "DNS"
            desc: (page.dnsServers.length > 0 ? page.dnsServers.join("  ") : "no servers")
                + (page.check === null ? "" : "  ·  " + (page.check.dns === null ? "not checked" : page.check.dns < 0
                   ? page.checkName + " not found" : page.checkName + " in " + page.check.dns + " ms"))
        }
    }

    // ── Ping / traceroute ───────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Ping and traceroute"
        icon: "󰛳"
        NetRow {
            first: true
            label: "Host"
            desc: page.errors.host ?? page.errors.count ?? "name or IP address"
            RowLayout {
                spacing: 8
                SearchField {
                    Layout.preferredWidth: 220
                    icon: ""; clearable: false
                    placeholderText: "1.1.1.1 or example.com"
                    text: page.host
                    error: page.errors.host !== undefined
                    onTextEdited: page.host = text
                    onAccepted: page.run("diag-ping")
                }
                SearchField {
                    Layout.preferredWidth: 60
                    icon: ""; clearable: false
                    text: page.count
                    error: page.errors.count !== undefined
                    onTextEdited: page.count = text
                }
                Text { text: "pings"; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
            }
        }
        NetRow {
            label: "Run"
            RowLayout {
                spacing: 6
                ActionButton {
                    icon: Jobs.isRunning("diag-ping") ? "󰜺" : "󰐊"
                    text: Jobs.isRunning("diag-ping") ? "Stop" : "Ping"
                    primary: !Jobs.isRunning("diag-ping")
                    onClicked: Jobs.isRunning("diag-ping") ? Jobs.cancel("diag-ping") : page.run("diag-ping")
                }
                ActionButton {
                    icon: Jobs.isRunning("diag-trace") ? "󰜺" : "󰑪"
                    text: Jobs.isRunning("diag-trace") ? "Stop" : "Traceroute"
                    onClicked: Jobs.isRunning("diag-trace") ? Jobs.cancel("diag-trace") : page.run("diag-trace")
                }
            }
        }
        ToolOutput { Layout.fillWidth: true; jobId: "diag-ping" }
        ToolOutput { Layout.fillWidth: true; jobId: "diag-trace" }
    }

    // ── Port ────────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Is a port open?"
        icon: "󰒍"
        NetRow {
            first: true
            label: "Host and port"
            desc: page.errors.portHost ?? page.errors.port ?? "TCP connect test (nc), e.g. ssh = 22, https = 443, rdp = 3389"
            RowLayout {
                spacing: 8
                SearchField {
                    Layout.preferredWidth: 200
                    icon: ""; clearable: false
                    placeholderText: "server"
                    text: page.portHost
                    error: page.errors.portHost !== undefined
                    onTextEdited: page.portHost = text
                    onAccepted: page.run("diag-port")
                }
                SearchField {
                    Layout.preferredWidth: 80
                    icon: ""; clearable: false
                    text: page.port
                    error: page.errors.port !== undefined
                    onTextEdited: page.port = text
                    onAccepted: page.run("diag-port")
                }
                ActionButton {
                    icon: "󰐊"; text: "Check"
                    interactive: !Jobs.isRunning("diag-port")
                    onClicked: page.run("diag-port")
                }
            }
        }
        ToolOutput { Layout.fillWidth: true; jobId: "diag-port" }
    }

    // ── Speed ───────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Internet speed"
        icon: "󰓅"
        NetRow {
            first: true
            label: "Speed test"
            desc: page.hasSpeedtestCli ? "speedtest-cli against the nearest speedtest.net server (~30 s, uses some data)"
                                       : "curl against speed.cloudflare.com (~30 s, about 35 MB; install speedtest-cli for speedtest.net)"
            ActionButton {
                icon: Jobs.isRunning("diag-speed") ? "󰜺" : "󰐊"
                text: Jobs.isRunning("diag-speed") ? "Stop" : "Start"
                primary: !Jobs.isRunning("diag-speed")
                onClicked: Jobs.isRunning("diag-speed") ? Jobs.cancel("diag-speed") : page.run("diag-speed")
            }
        }
        ToolOutput { Layout.fillWidth: true; jobId: "diag-speed" }
    }
}
