pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// NetworkManager for the settings app's Network page (modules/settings/network).
// Everything goes through `nmcli` (system connections can be changed by the
// logged-in user; global DNS and the hostname ask for the password through
// the shell's polkit agent, modules/polkit).
//
//   devices      interfaces with live state, addresses, DNS and DHCP lease
//   connections  saved profiles
//   load(uuid)   every setting of a profile (key → value, nmcli's names)
//   modify(...)  change settings; on an active connection they're re-applied
//   applySafely  the same, but reverted after 20s unless keep() is called
//
// While a page watches (`watchers` > 0), `nmcli monitor` triggers refreshes.
Singleton {
    id: root

    property var devices: []
    property var connections: []
    property var resolved: []          // [{ link, servers: [] }] from resolvectl
    property var globalDns: ({ servers: [], searches: [] })
    property string hostname: ""
    property bool networking: true
    property bool wifiEnabled: false
    property bool wifiHardware: false
    property string connectivity: ""
    property bool loaded: false
    property bool busy: false

    // last result of an action, shown as a toast: { text, error, id }
    property var message: null
    function say(text, error) { message = { text: text, error: !!error, id: Date.now() } }

    // ── Running commands ─────────────────────────────────────────────────────
    Component {
        id: procComponent
        Process {
            property var callback
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: code => {
                const cb = callback, o = out.text, e = err.text
                destroy()
                if (cb) cb(code, o, e)
            }
        }
    }

    // cb(code, stdout, stderr)
    function run(command, cb) {
        const p = procComponent.createObject(root, { command: command, callback: cb })
        p.running = true
    }

    // the first useful line of nmcli's complaint
    function errorText(e, fallback) {
        const l = String(e ?? "").split("\n").map(x => x.trim()).filter(x => x !== "" && !/^Warning:/.test(x))
        return (l[0] ?? fallback ?? "Failed").replace(/^Error: /, "")
    }

    // ── Reading ──────────────────────────────────────────────────────────────
    // terse output: fields split at ':' except "\:"
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

    function unescapeTerse(s) { return String(s).replace(/\\(.)/g, "$1") }

    readonly property string refreshScript:
        'echo @@CONNS; nmcli -t -f NAME,UUID,TYPE,DEVICE,AUTOCONNECT,ACTIVE,STATE,TIMESTAMP connection show\n'
        + 'echo @@DEVS; nmcli -t -f GENERAL,CAPABILITIES,IP4,DHCP4,IP6 device show\n'
        + 'echo @@GENERAL; nmcli -t -f STATE,CONNECTIVITY,WIFI-HW,WIFI general status; nmcli networking; nmcli general hostname\n'
        + 'echo @@RESOLVED; resolvectl dns 2>/dev/null\n'
        + 'echo @@GLOBALDNS; busctl --json=short get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager'
        + ' org.freedesktop.NetworkManager GlobalDnsConfiguration 2>/dev/null\n'

    property bool _refreshing: false
    property bool _again: false

    function refresh() {
        if (_refreshing) { _again = true; return }
        _refreshing = true
        run(["sh", "-c", refreshScript], (code, out) => {
            _refreshing = false
            parse(out)
            if (_again) { _again = false; refresh() }
        })
    }

    function parse(text) {
        const sections = {}
        let cur = null
        for (const line of text.split("\n")) {
            const m = /^@@([A-Z]+)$/.exec(line)
            if (m) { cur = m[1]; sections[cur] = []; continue }
            if (cur) sections[cur].push(line)
        }

        root.connections = (sections.CONNS ?? []).filter(l => l !== "").map(l => {
            const f = splitTerse(l)
            return { name: f[0], uuid: f[1], type: f[2], device: f[3], autoconnect: f[4] === "yes",
                     active: f[5] === "yes", state: f[6], timestamp: parseInt(f[7]) || 0 }
        })

        // devices: blocks of KEY:value separated by blank lines
        const devs = []
        let d = null
        for (const line of (sections.DEVS ?? []).concat([""])) {
            if (line === "") { if (d) devs.push(d); d = null; continue }
            const i = line.indexOf(":")
            if (i < 0) continue
            if (!d) d = {}
            const k = line.slice(0, i), v = line.slice(i + 1)
            const base = k.replace(/\[\d+\]$/, "")
            if (base !== k) (d[base] = d[base] ?? []).push(v)
            else d[k] = v
        }
        root.devices = devs.map(deviceFrom).filter(x => x.name !== "")

        const g = sections.GENERAL ?? []
        const st = splitTerse(g[0] ?? "")
        root.connectivity = st[1] ?? ""
        root.wifiHardware = st[2] === "enabled"
        root.wifiEnabled = st[3] === "enabled"
        root.networking = (g[1] ?? "enabled").trim() !== "disabled"
        root.hostname = (g[2] ?? "").trim()

        const res = []
        for (const line of sections.RESOLVED ?? []) {
            const m = /^(Global|Link \d+ \(([^)]+)\)):\s*(.*)$/.exec(line)
            if (m) res.push({ link: m[2] ?? "Global", servers: m[3].trim() === "" ? [] : m[3].trim().split(/\s+/) })
        }
        root.resolved = res

        let gd = { servers: [], searches: [] }
        try {
            const j = JSON.parse((sections.GLOBALDNS ?? []).join("\n")).data ?? {}
            gd = {
                servers: j.domains?.data?.["*"]?.data?.servers?.data ?? [],
                searches: j.searches?.data ?? []
            }
        } catch (e) {}
        root.globalDns = gd
        root.loaded = true
    }

    function deviceFrom(d) {
        const stateRaw = d["GENERAL.STATE"] ?? ""
        const code = parseInt(stateRaw) || 0
        const name = d["GENERAL.DEVICE"] ?? ""
        const opts = {}
        for (const o of d["DHCP4.OPTION"] ?? []) {
            const m = /^(\S+) = (.*)$/.exec(o)
            if (m) opts[m[1]] = m[2]
        }
        const routes = r => (r ?? []).map(x => {
            const m = /dst = ([^,]+), nh = ([^,]+), mt = (\d+)/.exec(x)
            return m ? { dest: m[1], via: m[2], metric: parseInt(m[3]) } : null
        }).filter(x => x)
        return {
            name: name,
            type: d["GENERAL.TYPE"] ?? "",
            vendor: d["GENERAL.VENDOR"] ?? "",
            product: d["GENERAL.PRODUCT"] ?? "",
            driver: d["GENERAL.DRIVER"] ?? "",
            mac: d["GENERAL.HWADDR"] ?? "",
            mtu: parseInt(d["GENERAL.MTU"]) || 0,
            stateCode: code,
            state: (/\((.*)\)/.exec(stateRaw)?.[1]) ?? stateRaw,
            external: /externally/.test(stateRaw),
            connection: d["GENERAL.CONNECTION"] ?? "",
            uuid: d["GENERAL.CON-UUID"] ?? "",
            managed: (d["GENERAL.NM-MANAGED"] ?? "yes") === "yes",
            software: (d["GENERAL.IS-SOFTWARE"] ?? "no") === "yes",
            sysVirtual: /\/virtual\//.test(d["GENERAL.UDI"] ?? ""),
            speed: (d["CAPABILITIES.SPEED"] ?? "").replace("unknown", ""),
            ip4: d["IP4.ADDRESS"] ?? [],
            gw4: d["IP4.GATEWAY"] ?? "",
            dns4: d["IP4.DNS"] ?? [],
            search4: d["IP4.SEARCHES"] ?? d["IP4.DOMAIN"] ?? [],
            routes4: routes(d["IP4.ROUTE"]),
            ip6: d["IP6.ADDRESS"] ?? [],
            gw6: d["IP6.GATEWAY"] ?? "",
            dns6: d["IP6.DNS"] ?? [],
            dhcp: Object.keys(opts).length === 0 ? null : {
                server: opts.dhcp_server_identifier ?? "",
                address: opts.ip_address ?? "",
                mask: opts.subnet_mask ?? "",
                routers: (opts.routers ?? "").split(" ").filter(x => x),
                dns: (opts.domain_name_servers ?? "").split(" ").filter(x => x),
                domain: opts.domain_name ?? "",
                leaseTime: parseInt(opts.dhcp_lease_time) || 0,
                expiry: parseInt(opts.expiry) || 0
            }
        }
    }

    // ── Watching ─────────────────────────────────────────────────────────────
    property int watchers: 0

    Process {
        running: root.watchers > 0
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: refreshTimer.restart() }
        onRunningChanged: if (running) root.refresh()
    }

    Timer { id: refreshTimer; interval: 500; onTriggered: root.refresh() }

    // the lease countdown and "expires in" texts tick with this
    property real now: Date.now()
    Timer { running: root.watchers > 0; interval: 1000; repeat: true; onTriggered: root.now = Date.now() }

    // ── One profile ──────────────────────────────────────────────────────────
    // cb({ settings: { "ipv4.method": "auto", … }, active: { "IP4.ADDRESS": [...] } } | null, error)
    function load(uuid, cb) {
        run(["nmcli", "-t", "connection", "show", uuid], (code, out, err) => {
            if (code !== 0) { cb(null, errorText(err, "Couldn't read the profile")); return }
            const settings = {}, active = {}
            for (const line of out.split("\n")) {
                const i = line.indexOf(":")
                if (i <= 0) continue
                const k = line.slice(0, i), v = line.slice(i + 1)
                if (/^[a-z0-9]/.test(k)) settings[k] = v
                else {
                    const base = k.replace(/\[\d+\]$/, "")
                    if (base !== k) (active[base] = active[base] ?? []).push(v)
                    else active[k] = v
                }
            }
            cb({ settings: settings, active: active }, "")
        })
    }

    // a secret (Wi-Fi password, …), only read when asked for
    function secret(uuid, key, cb) {
        run(["nmcli", "-s", "-g", key, "connection", "show", uuid], (code, out) => cb(code === 0 ? unescapeTerse(out.replace(/\n$/, "")) : ""))
    }

    // ── Changing ─────────────────────────────────────────────────────────────
    // changes: { key: value }. With `device` (the connection is active there)
    // the change is re-applied right away: `device reapply` keeps the link up
    // when it can, otherwise the connection is brought up again.
    readonly property string modifyScript:
        'uuid=$1; dev=$2; shift 2\n'
        + 'out=$(nmcli connection modify "$uuid" "$@" 2>&1) || { printf "%s\\n" "$out" >&2; exit 1; }\n'
        + 'if [ -n "$dev" ]; then\n'
        + '  nmcli device reapply "$dev" >/dev/null 2>&1 && exit 0\n'
        + '  out=$(nmcli --wait 20 connection up "$uuid" 2>&1) || { printf "Saved, but activating failed: %s\\n" "$out" >&2; exit 2; }\n'
        + 'fi'

    function modify(uuid, changes, device, cb) {
        const args = []
        for (const k of Object.keys(changes)) args.push(k, String(changes[k]))
        if (args.length === 0) { if (cb) cb(true, ""); return }
        root.busy = true
        run(["sh", "-c", modifyScript, "sh", uuid, device ?? ""].concat(args), (code, out, err) => {
            root.busy = false
            refreshTimer.restart()
            if (cb) cb(code === 0, code === 0 ? "" : errorText(err))
        })
    }

    // ── Safe apply: revert after 20s unless kept ─────────────────────────────
    // Kept across shell reloads (editing the config reloads the shell), so a
    // pending revert still happens: the countdown continues from `deadline`.
    property alias pending: persist.pending   // { uuid, device, name, old: { key: value } }
    property int countdown: 0

    PersistentProperties {
        id: persist
        reloadableId: "networkSafeApply"
        property var pending: null
        property real deadline: 0
        onLoaded: {
            if (!pending) return
            root.countdown = Math.ceil((deadline - Date.now()) / 1000)
            if (root.countdown <= 0) root.revert()
            else safeTimer.restart()
        }
    }

    function applySafely(uuid, name, device, changes, old, cb) {
        modify(uuid, changes, device, (ok, err) => {
            if (ok && device) {
                root.pending = { uuid: uuid, device: device, name: name, old: old }
                persist.deadline = Date.now() + 20000
                root.countdown = 20
                safeTimer.restart()
            }
            if (cb) cb(ok, err)
        })
    }

    function keep() {
        safeTimer.stop()
        if (root.pending) say("Kept the new settings of " + root.pending.name)
        root.pending = null
    }

    function revert() {
        safeTimer.stop()
        const p = root.pending
        root.pending = null
        if (!p) return
        modify(p.uuid, p.old, p.device, (ok, err) =>
            say(ok ? "Reverted " + p.name : "Reverting failed: " + err, !ok))
    }

    Timer {
        id: safeTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown = Math.ceil((persist.deadline - Date.now()) / 1000)
            if (root.countdown <= 0) root.revert()
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    // cmd → toast with `done` on success, nmcli's error otherwise
    function act(cmd, done, cb) {
        root.busy = true
        run(cmd, (code, out, err) => {
            root.busy = false
            refreshTimer.restart()
            if (code === 0) { if (done) say(done) }
            else say(errorText(err), true)
            if (cb) cb(code === 0, out)
        })
    }

    function up(uuid, device, name) {
        act(["nmcli", "--wait", "30", "connection", "up", uuid].concat(device ? ["ifname", device] : []),
            "Connected " + (name ?? ""))
    }
    function down(uuid, name) { act(["nmcli", "connection", "down", uuid], "Disconnected " + (name ?? "")) }
    function deviceConnect(dev) { act(["nmcli", "--wait", "30", "device", "connect", dev], dev + " connected") }
    function deviceDisconnect(dev) { act(["nmcli", "device", "disconnect", dev], dev + " disconnected") }
    // re-runs DHCP etc. without dropping the link where possible
    function renew(dev) {
        act(["sh", "-c", 'nmcli device reapply "$1" || nmcli --wait 30 device connect "$1"', "sh", dev], "Renewed " + dev)
    }
    function setManaged(dev, on) { act(["nmcli", "device", "set", dev, "managed", on ? "yes" : "no"], dev + (on ? " managed again" : " left alone by NetworkManager")) }
    function remove(uuid, name) { act(["nmcli", "connection", "delete", uuid], "Deleted " + name) }
    function clone(uuid, name, cb) { act(["nmcli", "connection", "clone", uuid, name], "Duplicated as " + name, cb) }
    function setNetworking(on) { act(["nmcli", "networking", on ? "on" : "off"], "Networking " + (on ? "on" : "off")) }
    function setWifi(on) { act(["nmcli", "radio", "wifi", on ? "on" : "off"], "Wi-Fi " + (on ? "on" : "off")) }
    // asks for the password (polkit)
    function setHostname(h) { act(["nmcli", "general", "hostname", h], "Hostname set to " + h) }

    // add a profile; cb(uuid) with the new one's uuid
    function add(type, name, ifname, extra, cb) {
        const cmd = ["nmcli", "-t", "connection", "add", "type", type, "con-name", name]
            .concat(ifname ? ["ifname", ifname] : []).concat(extra ?? [])
        act(cmd, "Added " + name, (ok, out) => {
            const m = /\(([0-9a-f-]{36})\)/.exec(out)
            if (cb) cb(ok && m ? m[1] : "")
        })
    }

    // VPN / WireGuard file (openvpn .ovpn, wireguard .conf, …)
    function importFile(kind, file, cb) {
        act(["nmcli", "connection", "import", "type", kind, "file", file], "Imported " + file.replace(/.*\//, ""), cb)
    }

    // ── Global DNS (NetworkManager's GlobalDnsConfiguration) ─────────────────
    // overrides the DNS of every connection; empty `servers` turns it off.
    // Asks for the password (polkit).
    function setGlobalDns(servers, searches) {
        let args = []
        if (servers.length === 0) args = ["a{sv}", "0"]
        else {
            args = ["a{sv}", String(searches.length > 0 ? 2 : 1)]
            if (searches.length > 0) args = args.concat(["searches", "as", String(searches.length)], searches)
            args = args.concat(["domains", "a{sv}", "1", "*", "a{sv}", "1", "servers", "as", String(servers.length)], servers)
        }
        act(["busctl", "set-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
             "org.freedesktop.NetworkManager", "GlobalDnsConfiguration"].concat(args),
            servers.length === 0 ? "Global DNS off, every network uses its own" : "Global DNS set to " + servers.join(", "))
    }

    // ── DNS tools ────────────────────────────────────────────────────────────
    // cb(ok, text)
    function lookup(name, cb) {
        const t0 = Date.now()
        run(["resolvectl", "query", "--no-pager", name], (code, out, err) => {
            const lines = (code === 0 ? out : err).split("\n").filter(l => l.trim() !== "" && !/^--/.test(l))
            cb(code === 0, lines.join("\n") + (code === 0 ? "\n" + (Date.now() - t0) + " ms" : ""))
        })
    }
    function flushDns() { act(["resolvectl", "flush-caches"], "DNS cache flushed") }

    // ── Helpers for the page ─────────────────────────────────────────────────
    readonly property var typeInfo: ({
        "802-3-ethernet": { label: "Ethernet", icon: "󰈀" }, "ethernet": { label: "Ethernet", icon: "󰈀" },
        "802-11-wireless": { label: "Wi-Fi", icon: "󰖩" }, "wifi": { label: "Wi-Fi", icon: "󰖩" },
        "bridge": { label: "Bridge", icon: "󰌘" }, "bond": { label: "Bond", icon: "󰌷" },
        "vlan": { label: "VLAN", icon: "󰛳" }, "wireguard": { label: "WireGuard", icon: "󰒃" },
        "vpn": { label: "VPN", icon: "󰒃" }, "tun": { label: "Tunnel", icon: "󰒃" },
        "loopback": { label: "Loopback", icon: "󰑖" }, "veth": { label: "Virtual Ethernet", icon: "󰡨" },
        "dummy": { label: "Dummy", icon: "󰡨" }, "gsm": { label: "Mobile", icon: "󰄜" },
        "bluetooth": { label: "Bluetooth", icon: "󰂯" }, "wifi-p2p": { label: "Wi-Fi P2P", icon: "󰖩" },
        "macvlan": { label: "MACVLAN", icon: "󰛳" }, "ip-tunnel": { label: "IP tunnel", icon: "󰒃" }
    })
    function typeLabel(t) { return typeInfo[t]?.label ?? t }
    function typeIcon(t) { return typeInfo[t]?.icon ?? "󰛳" }

    // virtual = software / sysfs-virtual devices (docker, bridges, veth, vmnet,
    // tunnels, lo) or a name matching the user's patterns
    function matchesPattern(name, patterns) {
        return patterns.some(p => p !== "" && new RegExp("^" + p.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$").test(name))
    }
}
