pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import qs.services
import qs.services.lib

// What the bar, the control center tile and "Wi-Fi off while wired" show:
// wired / Wi-Fi connected, signal, Wi-Fi on/off.
//
// Normally straight from Quickshell.Networking. But that picks its
// NetworkManager backend once, when the shell starts, and never tries again:
// if NetworkManager wasn't running then (it failed at boot and was restarted
// later), Networking stays empty until `qs` itself restarts — a config
// reload doesn't help, it's a process-wide singleton. Then (`fallback`) the
// state comes from nmcli instead, refreshed by `nmcli monitor` (restarted
// whenever it exits) plus a slow poll for the signal strength.
Singleton {
    id: root

    readonly property bool fallback: Networking.backend !== NetworkBackendType.NetworkManager

    // ── native (Quickshell.Networking) ──
    readonly property var wiredDevice: fallback ? null : Devices.pick(Networking.devices.values, DeviceType.Wired)
    readonly property var wifiDevice: fallback ? null : Devices.pick(Networking.devices.values, DeviceType.Wifi)
    readonly property var wifiNetwork: wifiDevice?.networks?.values.find(n => n.connected) ?? null

    // ── nmcli (fallback) ──
    property bool nmRunning: false
    property bool nmWired: false
    property bool nmWifiDevice: false
    property bool nmWifiOn: false
    property string nmSsid: ""          // "" = no Wi-Fi connected
    property real nmSignal: 0

    // ── what everyone reads ──
    readonly property bool wiredConnected: fallback ? nmWired : (wiredDevice?.connected ?? false)
    readonly property bool hasWifiDevice: fallback ? nmWifiDevice : wifiDevice !== null
    readonly property bool wifiEnabled: fallback ? nmWifiOn : Networking.wifiEnabled
    readonly property bool wifiConnected: fallback ? nmSsid !== "" : wifiNetwork !== null
    readonly property string wifiName: fallback ? nmSsid : (wifiNetwork?.name ?? "")
    readonly property real wifiSignal: {             // 0..1
        if (fallback) return nmSignal
        const raw = wifiNetwork?.signalStrength ?? 0
        return raw > 1 ? raw / 100 : raw
    }

    function setWifiEnabled(on) {
        if (!fallback) { Networking.wifiEnabled = on; return }
        nmWifiOn = on
        Jobs.run(["nmcli", "radio", "wifi", on ? "on" : "off"], () => refresh())
    }

    // device lines "TYPE:STATE:DEVICE", then the Wi-Fi radio, then the Wi-Fi in use
    readonly property string script:
        'nmcli -t -f RUNNING general 2>/dev/null | head -n1\n'
        + 'echo @@DEV; nmcli -t -f TYPE,STATE device 2>/dev/null\n'
        + 'echo @@RADIO; nmcli radio wifi 2>/dev/null\n'
        + 'echo @@WIFI; nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null | grep "^\\*" | head -n1\n'

    property bool _busy: false
    property bool _again: false
    function refresh() {
        if (!fallback) return
        if (_busy) { _again = true; return }
        _busy = true
        Jobs.run(["sh", "-c", script], (code, out) => {
            _busy = false
            parse(out)
            if (_again) { _again = false; refresh() }
        })
    }

    // nmcli -t fields: split at ':' except "\:"
    function splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur)
        return out
    }

    function parse(text) {
        const sec = { HEAD: [] }
        let cur = "HEAD"
        for (const l of text.split("\n")) {
            const m = /^@@([A-Z]+)$/.exec(l)
            if (m) { cur = m[1]; sec[cur] = []; continue }
            if (l.trim() !== "") sec[cur].push(l.trim())
        }
        nmRunning = (sec.HEAD[0] ?? "") === "running"
        const devs = (sec.DEV ?? []).map(l => splitTerse(l))
        // "connected (externally)" counts too (a cable NM didn't bring up itself);
        // unmanaged virtual ones (vmnet) are never "connected"
        nmWired = devs.some(d => d[0] === "ethernet" && /^connected/.test(d[1] ?? ""))
        nmWifiDevice = devs.some(d => d[0] === "wifi")
        nmWifiOn = (sec.RADIO?.[0] ?? "") === "enabled"
        const connectedWifi = devs.some(d => d[0] === "wifi" && /^connected/.test(d[1] ?? ""))
        const w = sec.WIFI?.[0] ? splitTerse(sec.WIFI[0]) : null
        nmSsid = connectedWifi ? (w?.[2] || "Wi-Fi") : ""
        nmSignal = connectedWifi && w ? Math.max(0, Math.min(1, (parseInt(w[1]) || 0) / 100)) : 0
    }

    // fallback only: every change NetworkManager reports → refresh (debounced)
    Process {
        id: monitor
        running: root.fallback
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: _ => debounce.restart() }
        // NetworkManager down, nmcli missing…: try again in a few seconds
        onExited: if (root.fallback) restartMonitor.restart()
    }
    Timer { id: restartMonitor; interval: 5000; onTriggered: { monitor.running = true; root.refresh() } }
    Timer { id: debounce; interval: 400; onTriggered: root.refresh() }
    // the signal strength doesn't come through nmcli monitor
    Timer { interval: 30000; repeat: true; running: root.fallback; onTriggered: root.refresh() }

    onFallbackChanged: refresh()
    Component.onCompleted: {
        if (fallback) console.warn("NetLink: Quickshell.Networking has no NetworkManager backend (NetworkManager wasn't running when the shell started); using nmcli")
        refresh()
    }
}
