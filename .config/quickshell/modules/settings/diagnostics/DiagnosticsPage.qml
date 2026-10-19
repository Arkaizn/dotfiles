import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"
// Network diagnostics: ping, traceroute, port check, speed test. Every field
// is checked (Valid.js) before anything runs; commands are argument lists;
// each job can be cancelled and is stopped when the page closes.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var jobIds: ["diag-ping", "diag-trace", "diag-port", "diag-speed"]
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
            argv = ["speedtest-cli", "--simple", "--secure"]
            opts.timeout = 120000
        }
        errors = e
        if (argv) Jobs.start(id, argv, opts)
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
            desc: "speedtest-cli against the nearest speedtest.net server (~30 s, uses some data)"
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
