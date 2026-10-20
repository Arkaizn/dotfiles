.pragma library

// Parsers for services/Vpn.qml (imported as VpnParse) (VPN status from the CLIs), kept pure so they
// can be unit-tested. Every result has `installed` and `on`.

// `tailscale status --json`
function tailscale(code, out) {
    let d
    try { d = JSON.parse(out) } catch (e) { return { installed: true, on: false, state: code === 0 ? "unknown" : "not running", tailnet: "", ip: "", peers: "", error: (out || "").trim().split("\n")[0] } }
    const peers = Object.values(d.Peer ?? {})
    return {
        installed: true,
        state: d.BackendState ?? "unknown",          // Running | Stopped | NeedsLogin | Starting | NoState
        on: d.BackendState === "Running",
        tailnet: d.CurrentTailnet?.Name ?? "",
        ip: (d.Self?.TailscaleIPs ?? [])[0] ?? "",
        peers: peers.length > 0 ? peers.filter(p => p.Online).length + " / " + peers.length + " online" : "",
        error: ""
    }
}

// `netbird status --json`
function netbird(code, out) {
    let d
    try { d = JSON.parse(out) } catch (e) { return { installed: true, on: false, state: "not running", ip: "", peers: "", needsLogin: false, error: (out || "").trim().split("\n")[0] } }
    const state = d.daemonStatus ?? "unknown"         // Connected | Idle | NeedsLogin | LoginFailed | SessionExpired | Connecting
    const p = d.peers ?? {}
    return {
        installed: true,
        state: state,
        on: state === "Connected",
        needsLogin: ["NeedsLogin", "LoginFailed", "SessionExpired"].includes(state),
        ip: (d.netbirdIp ?? "").replace(/\/\d+$/, ""),
        peers: (p.total ?? 0) > 0 ? (p.connected ?? 0) + " / " + p.total + " connected" : "",
        error: d.management?.connected === false ? (d.management?.error ?? "").replace(/^rpc error: code = \w+ desc = /, "") : ""
    }
}

// `nmcli -t -f NAME,UUID,TYPE,ACTIVE connection show` → VPN / WireGuard profiles
// (terse output: ":" separates fields, "\:" is a colon inside one)
function nmVpns(out) {
    return (out ?? "").split("\n").filter(l => l !== "").map(l => {
        const f = l.split(/(?<!\\):/).map(x => x.replace(/\\:/g, ":"))
        return { name: f[0] ?? "", uuid: f[1] ?? "", type: f[2] ?? "", active: f[3] === "yes" }
    }).filter(c => c.type === "vpn" || c.type === "wireguard")
}
