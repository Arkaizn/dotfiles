pragma Singleton
import Quickshell
import QtQuick
import qs.services
import qs.services.lib

// VPNs for Settings → Network → VPN and the control center's VPN tile:
//   tailscale   { installed, on, state, tailnet, ip, peers, error }
//   netbird     { installed, on, state, needsLogin, ip, peers, error }
//   profiles    NetworkManager VPN / WireGuard profiles [{ name, uuid, type, active }]
// (parsers: services/lib/VpnParse.js). Read while something watches (watchers > 0:
// the VPN tab, an open control center), every 5 s and right after a switch.
// Switching:
//   Tailscale  its local API, like its own tray: only "want running" changes
//              (needs the operator user — `sudo tailscale set --operator=$USER`)
//   NetBird    `netbird up` / `down`; up opens the browser when the login expired
//   profiles   `nmcli connection up` / `down`
Singleton {
    id: root

    property int watchers: 0
    property var tailscale: ({ installed: false, on: false })
    property var netbird: ({ installed: false, on: false })
    property var profiles: []
    property string busy: ""                // "tailscale" | "netbird" | <uuid> while switching
    property string message: ""             // last error from a switch

    readonly property bool available: tailscale.installed || netbird.installed || profiles.length > 0
    readonly property var upNames: [tailscale.on ? "Tailscale" : "", netbird.on ? "NetBird" : ""]
        .concat(profiles.filter(p => p.active).map(p => p.name)).filter(n => n !== "")

    readonly property string tsSocket: "/var/run/tailscale/tailscaled.sock"

    function refresh() {
        Jobs.which(["tailscale", "netbird", "nmcli"], have => {
            if (have.tailscale) Jobs.run(["tailscale", "status", "--json"], (code, out, err) => root.tailscale = VpnParse.tailscale(code, out || err))
            else root.tailscale = { installed: false, on: false }
            if (have.netbird) Jobs.run(["netbird", "status", "--json"], (code, out, err) => root.netbird = VpnParse.netbird(code, out || err))
            else root.netbird = { installed: false, on: false }
            if (have.nmcli) Jobs.run(["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"], (code, out) => root.profiles = VpnParse.nmVpns(out))
        })
    }
    Timer { running: root.watchers > 0; interval: 5000; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    function done(what, ok, text) {
        busy = ""
        message = ok ? "" : what + ": " + (text.trim().split("\n").pop() || "failed")
        refresh()
    }

    function setTailscale(on) {
        busy = "tailscale"
        Jobs.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--unix-socket", tsSocket, "-X", "PATCH",
                  "-H", "Sec-Tailscale: localapi", "-H", "Content-Type: application/json",
                  "-d", JSON.stringify({ WantRunningSet: true, WantRunning: on }), "http://local-tailscaled.sock/localapi/v0/prefs"],
                 (code, out) => {
            const http = out.trim()
            done("Tailscale", code === 0 && http === "200",
                 http === "403" ? "not allowed — run once: sudo tailscale set --operator=$USER" : "failed (HTTP " + (http || "?") + ")")
        })
    }

    function setNetbird(on) {
        busy = "netbird"
        // `up` waits for the browser login when it expired (up to 5 min)
        Jobs.start("vpn-netbird", ["netbird", on ? "up" : "down"], {
            timeout: on ? 300000 : 30000,
            onExit: code => root.done("NetBird", code === 0, Jobs.state("vpn-netbird").lines.map(l => l.text).join("\n"))
        })
    }

    function setProfile(uuid, on) {
        busy = uuid
        Jobs.run(["nmcli", "connection", on ? "up" : "down", "uuid", uuid], (code, out, err) => root.done("VPN", code === 0, err || out))
    }
}
