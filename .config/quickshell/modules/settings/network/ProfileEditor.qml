import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "Net.js" as Net

// Editor for one NetworkManager profile. Every change is a draft (`edits`)
// until Apply in the bar at the bottom of the window; on an active profile it
// goes through the page's safe apply (reverted after 20s unless kept).
// "All settings" lists every property nmcli knows, so nothing that
// nm-connection-editor can set is out of reach.
ColumnLayout {
    id: ed

    required property string uuid
    property var page
    property string tab: "general"
    signal back()

    // tabs slide in from the side they sit on
    property int tabDir: 1
    function setTab(t) {
        if (t === tab) return
        const order = tabs.map(x => x.value)
        tabDir = order.indexOf(t) > order.indexOf(tab) ? 1 : -1
        tab = t
    }

    property var orig: ({})
    property var active: ({})
    property var edits: ({})
    property bool loaded: false
    property string loadError: ""
    property var secrets: ({})            // key → revealed value

    readonly property string type: orig["connection.type"] ?? ""
    readonly property string device: (active["GENERAL.DEVICES"] ?? "").split(",")[0] ?? ""
    readonly property bool isActive: device !== ""
    readonly property int changeCount: Object.keys(edits).length

    spacing: 14

    function load() {
        Network.load(uuid, (p, err) => {
            if (!p) { ed.loadError = err; return }
            ed.orig = p.settings
            ed.active = p.active
            ed.edits = {}
            ed.secrets = {}
            ed.loaded = true
        })
    }
    Component.onCompleted: load()

    // ── Values ──────────────────────────────────────────────────────────────
    function raw(k) { const v = orig[k]; return v === undefined || v === "--" ? "" : v }
    function val(k) { return edits[k] !== undefined ? edits[k] : raw(k) }
    function changed(k) { return edits[k] !== undefined }
    function set(k, v) {
        const e = Object.assign({}, edits)
        if (String(v) === raw(k)) delete e[k]
        else e[k] = String(v)
        edits = e
    }
    function list(k) { return Net.splitList(val(k)) }
    function setList(k, a) { set(k, Net.joinList(a)) }
    function yes(k) { return val(k) === "yes" }
    function setYes(k, on) { set(k, on ? "yes" : "no") }
    function has(prefix) { return Object.keys(orig).some(k => k.startsWith(prefix + ".")) }
    // "-1 (default)", "2 (yes)", "yes" … → the number nmcli takes
    function ternary(k, words) {
        const v = val(k)
        const n = parseInt(v)
        if (!isNaN(n)) return String(n)
        const i = (words ?? ["no", "yes"]).indexOf(v)
        return i >= 0 ? String(i) : "-1"
    }
    function isSecret(k) { return raw(k) === "<hidden>" || /(psk|password|private-key|secret|wep-key\d)$/.test(k) }

    // problems that block Apply
    readonly property var problems: {
        const p = []
        const chk = (k, fn, what) => { for (const x of list(k)) { const e = fn(x); if (e) { p.push(what + " " + x + ": " + e); break } } }
        chk("ipv4.addresses", Net.ipv4Cidr, "IPv4 address")
        chk("ipv4.dns", Net.ipv4, "IPv4 DNS")
        chk("ipv6.addresses", Net.ipv6Cidr, "IPv6 address")
        chk("ipv6.dns", Net.ipv6, "IPv6 DNS")
        chk("ipv4.routes", Net.route4, "IPv4 route")
        chk("ipv6.routes", Net.route6, "IPv6 route")
        if (val("ipv4.gateway") !== "" && Net.ipv4(val("ipv4.gateway"))) p.push("IPv4 gateway: " + Net.ipv4(val("ipv4.gateway")))
        if (val("ipv6.gateway") !== "" && Net.ipv6(val("ipv6.gateway"))) p.push("IPv6 gateway: " + Net.ipv6(val("ipv6.gateway")))
        if (val("ipv4.method") === "manual" && list("ipv4.addresses").length === 0) p.push("Manual IPv4 needs an address")
        if (val("ipv6.method") === "manual" && list("ipv6.addresses").length === 0) p.push("Manual IPv6 needs an address")
        if (val("connection.id").trim() === "") p.push("The profile needs a name")
        return p
    }

    function apply() {
        const old = {}
        for (const k of Object.keys(edits)) if (k !== "remove" && !isSecret(k)) old[k] = raw(k)
        // removing a whole setting can't be undone by the timer: no safe apply then
        page.applyChanges(uuid, val("connection.id"), isActive ? device : "", edits, old,
                          ok => { if (ok) ed.load() }, !("remove" in edits))
    }

    // IPv4/IPv6 method switch with the "simple switch" rules
    function setMethod(fam, m) {
        const cur = val(fam + ".method")
        if (m === cur) return
        set(fam + ".method", m)
        if (m === "manual" && list(fam + ".addresses").length === 0) {
            // fill from what's live now
            const big = fam === "ipv4" ? "IP4" : "IP6"
            const addrs = (active[big + ".ADDRESS"] ?? []).filter(a => !/^fe80:/i.test(a))
            if (addrs.length > 0) setList(fam + ".addresses", addrs.slice(0, 1))
            if (val(fam + ".gateway") === "" && (active[big + ".GATEWAY"] ?? "") !== "") set(fam + ".gateway", active[big + ".GATEWAY"])
            if (list(fam + ".dns").length === 0 && (active[big + ".DNS"] ?? []).length > 0) setList(fam + ".dns", active[big + ".DNS"])
        } else if (["auto", "dhcp", "link-local", "disabled", "ignore"].includes(m)) {
            if (list(fam + ".addresses").length > 0) set(fam + ".addresses", "")
            if (val(fam + ".gateway") !== "") set(fam + ".gateway", "")
        }
    }

    readonly property var dnsPresets4: [
        { label: "Cloudflare", values: ["1.1.1.1", "1.0.0.1"] },
        { label: "Quad9", values: ["9.9.9.9", "149.112.112.112"] },
        { label: "Google", values: ["8.8.8.8", "8.8.4.4"] }
    ]
    readonly property var dnsPresets6: [
        { label: "Cloudflare", values: ["2606:4700:4700::1111", "2606:4700:4700::1001"] },
        { label: "Quad9", values: ["2620:fe::fe", "2620:fe::9"] },
        { label: "Google", values: ["2001:4860:4860::8888", "2001:4860:4860::8844"] }
    ]

    readonly property var linkTab: ({
        "802-3-ethernet": { label: "Ethernet", icon: "󰈀" }, "802-11-wireless": { label: "Wi-Fi", icon: "󰖩" },
        "bridge": { label: "Bridge", icon: "󰌘" }, "bond": { label: "Bond", icon: "󰌷" },
        "vlan": { label: "VLAN", icon: "󰛳" }, "wireguard": { label: "WireGuard", icon: "󰒃" }
    })[type] ?? null

    readonly property var tabs: [{ label: "General", value: "general", icon: "󰒓" }]
        .concat(has("ipv4") ? [{ label: "IPv4", value: "ipv4", icon: "󰩟" }] : [])
        .concat(has("ipv6") ? [{ label: "IPv6", value: "ipv6", icon: "󰩠" }] : [])
        .concat(linkTab ? [{ label: linkTab.label, value: "link", icon: linkTab.icon }] : [])
        .concat([{ label: "All settings", value: "all", icon: "󰒓" }])

    // ── Shared bits ─────────────────────────────────────────────────────────
    component Field: SearchField {
        property string key
        Layout.preferredWidth: 240
        implicitHeight: Properties.buttonHeight
        icon: ""
        clearable: false
        text: ed.val(key)
        onEditingFinished: if (text !== ed.val(key)) ed.set(key, text)
    }

    component Toggle: ToggleSwitch {
        property string key
        property bool invert: false
        checked: ed.yes(key) !== invert
        onToggled: v => ed.setYes(key, v !== invert)
    }

    // tab body: slides + fades in when picked
    component Pane: ColumnLayout {
        id: pane
        property string key
        Layout.fillWidth: true
        spacing: 16
        visible: ed.tab === key
        property real slide: 0
        transform: Translate { x: pane.slide }
        // started by the view change itself (not by the editor / page appearing)
        Connections {
            target: ed
            function onTabChanged() { if (ed.tab === pane.key) paneIn.restart() }
        }
        ParallelAnimation {
            id: paneIn
            NumberAnimation { target: pane; property: "opacity"; from: 0; to: 1; duration: 220 }
            NumberAnimation { target: pane; property: "slide"; from: 36 * ed.tabDir; to: 0; duration: 280; easing.type: Easing.OutCubic }
        }
    }

    // ── Header ──────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: headRow.implicitHeight + 24
        radius: 14
        color: "#27000000"
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        RowLayout {
            id: headRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 12 }
            spacing: 12

            IconButton {
                icon: "󰁍"
                tooltip: "Back"
                onClicked: ed.back()
            }
            Rectangle {
                width: 40; height: 40; radius: 20
                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, ed.isActive ? 0.18 : 0.06)
                border.width: 1.5
                border.color: ed.isActive ? Colors.color6 : Qt.rgba(1, 1, 1, 0.2)
                Text {
                    anchors.centerIn: parent
                    text: Network.typeIcon(ed.type)
                    color: ed.isActive ? Colors.color6 : Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 18
                    font.family: Properties.fontFamily
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: ed.val("connection.id") || "…"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: [Network.typeLabel(ed.type), ed.isActive ? "active on " + ed.device : "not active",
                           ed.raw("connection.interface-name") ? "for " + ed.raw("connection.interface-name") : null]
                          .filter(x => x).join("  ·  ")
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
            ActionButton {
                icon: ed.isActive ? "󰌙" : "󰌘"
                text: ed.isActive ? "Disconnect" : "Connect"
                onClicked: ed.isActive ? Network.down(ed.uuid, ed.val("connection.id")) : Network.up(ed.uuid, "", ed.val("connection.id"))
            }
            IconButton {
                icon: "󰆏"
                tooltip: "Duplicate"
                onClicked: Network.clone(ed.uuid, ed.raw("connection.id") + " (copy)")
            }
            IconButton {
                id: delBtn
                property bool armed: false
                icon: "󰆴"
                tooltip: armed ? "Click again to delete" : "Delete"
                active: armed
                textColor: "#f38ba8"
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return }
                    Network.remove(ed.uuid, ed.raw("connection.id"))
                    ed.back()
                }
                Timer { id: disarm; interval: 3000; onTriggered: delBtn.armed = false }
            }
        }
    }

    Text {
        visible: ed.loadError !== ""
        text: "󰀦  " + ed.loadError
        color: "#f38ba8"
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }

    Segmented {
        Layout.alignment: Qt.AlignLeft
        visible: ed.loaded
        options: ed.tabs
        value: ed.tab
        onEdited: v => ed.setTab(v)
    }

    // ── General ─────────────────────────────────────────────────────────────
    Pane {
        key: "general"
        NetCard {
            Layout.fillWidth: true
            title: "Profile"
            NetRow {
                first: true
                label: "Name"
                changed: ed.changed("connection.id")
                Field { key: "connection.id" }
            }
            NetRow {
                label: "Interface"
                desc: "Only use this profile on this interface"
                changed: ed.changed("connection.interface-name")
                DropdownControl {
                    implicitWidth: 240
                    readonly property string cur: ed.val("connection.interface-name")
                    options: [{ label: "Any interface", value: "" }]
                        .concat(Network.devices.filter(d => d.type !== "loopback").map(d => ({ label: d.name, value: d.name, hint: Network.typeLabel(d.type) })))
                        .concat(cur !== "" && !Network.devices.some(d => d.name === cur) ? [{ label: cur, value: cur, hint: "not present" }] : [])
                    value: cur
                    onEdited: v => ed.set("connection.interface-name", v)
                }
            }
            NetRow {
                label: "Connect automatically"
                changed: ed.changed("connection.autoconnect")
                Toggle { key: "connection.autoconnect" }
            }
            NetRow {
                sub: true
                visible: ed.yes("connection.autoconnect")
                label: "Priority"
                desc: "When several profiles fit, the highest wins"
                changed: ed.changed("connection.autoconnect-priority")
                Field { key: "connection.autoconnect-priority"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "Available to all users"
                desc: "Off: only you can use it"
                changed: ed.changed("connection.permissions")
                ToggleSwitch {
                    checked: ed.val("connection.permissions") === ""
                    onToggled: v => ed.set("connection.permissions", v ? "" : "user:" + (Quickshell.env("USER") ?? ""))
                }
            }
            NetRow {
                label: "Metered"
                desc: "Apps avoid big downloads on metered networks"
                changed: ed.changed("connection.metered")
                Segmented {
                    small: true
                    options: [{ label: "Auto", value: "unknown" }, { label: "Yes", value: "yes" }, { label: "No", value: "no" }]
                    value: ed.val("connection.metered").replace(/ .*/, "") || "unknown"
                    onEdited: v => ed.set("connection.metered", v)
                }
            }
        }

        NetCard {
            Layout.fillWidth: true
            title: "Name resolution & firewall"
            NetRow {
                first: true
                label: "DNS over TLS"
                changed: ed.changed("connection.dns-over-tls")
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "-1" }, { label: "Off", value: "0" }, { label: "Opportunistic", value: "1" }, { label: "Strict", value: "2" }]
                    value: ed.ternary("connection.dns-over-tls", ["no", "opportunistic", "yes"])
                    onEdited: v => ed.set("connection.dns-over-tls", v)
                }
            }
            NetRow {
                label: "mDNS"
                desc: "Resolve .local names"
                changed: ed.changed("connection.mdns")
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "-1" }, { label: "Off", value: "0" }, { label: "Resolve", value: "1" }, { label: "On", value: "2" }]
                    value: ed.ternary("connection.mdns", ["no", "resolve", "yes"])
                    onEdited: v => ed.set("connection.mdns", v)
                }
            }
            NetRow {
                label: "LLMNR"
                changed: ed.changed("connection.llmnr")
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "-1" }, { label: "Off", value: "0" }, { label: "Resolve", value: "1" }, { label: "On", value: "2" }]
                    value: ed.ternary("connection.llmnr", ["no", "resolve", "yes"])
                    onEdited: v => ed.set("connection.llmnr", v)
                }
            }
            NetRow {
                label: "Firewall zone"
                desc: "firewalld zone, empty for the default"
                changed: ed.changed("connection.zone")
                Field { key: "connection.zone"; placeholderText: "default" }
            }
        }
    }

    // ── IPv4 / IPv6 ─────────────────────────────────────────────────────────
    component IpPane: Pane {
        id: ip
        required property string fam            // "ipv4" | "ipv6"
        readonly property bool v4: fam === "ipv4"
        readonly property string method: ed.val(fam + ".method")
        readonly property bool dhcp: method === "auto" || method === "dhcp"
        key: fam

        NetCard {
            Layout.fillWidth: true
            title: "Address"
            NetRow {
                first: true
                wide: true
                label: "Method"
                desc: ip.method === "auto" ? (ip.v4 ? "Address, gateway and DNS from the DHCP server" : "Router advertisements, DHCPv6 if the router asks")
                    : ip.method === "dhcp" ? "DHCPv6 only"
                    : ip.method === "manual" ? "Everything set by hand below"
                    : ip.method === "link-local" ? "Self-assigned link-local address only"
                    : ip.method === "shared" ? "Shares this computer's connection: runs a DHCP server + NAT on this interface"
                    : ip.method === "ignore" ? "NetworkManager leaves IPv6 alone"
                    : "No " + (ip.v4 ? "IPv4" : "IPv6") + " on this profile"
                changed: ed.changed(ip.fam + ".method")
                Segmented {
                    options: ip.v4
                        ? [{ label: "DHCP", value: "auto", icon: "󰑓" }, { label: "Manual", value: "manual", icon: "󰏫" },
                           { label: "Link-local", value: "link-local" }, { label: "Shared", value: "shared", icon: "󰒍" },
                           { label: "Off", value: "disabled" }]
                        : [{ label: "Auto", value: "auto", icon: "󰑓" }, { label: "DHCP", value: "dhcp" },
                           { label: "Manual", value: "manual", icon: "󰏫" }, { label: "Link-local", value: "link-local" },
                           { label: "Shared", value: "shared" }, { label: "Ignore", value: "ignore" }, { label: "Off", value: "disabled" }]
                    value: ip.method
                    onEdited: v => ed.setMethod(ip.fam, v)
                }
            }
            Reveal {
                open: !["disabled", "ignore", "link-local"].includes(ip.method)
                NetRow {
                    wide: true
                    label: ip.method === "manual" ? "Addresses" : "Extra static addresses"
                    desc: ip.method === "manual" ? "With prefix, e.g. " + (ip.v4 ? "192.168.1.10/24" : "fd00::10/64") + " (a bare address gets /" + (ip.v4 ? "24" : "64") + ")"
                        : "Optional, used alongside " + (ip.method === "shared" ? "sharing" : "DHCP")
                    changed: ed.changed(ip.fam + ".addresses")
                    ListField {
                        Layout.fillWidth: true
                        values: ed.list(ip.fam + ".addresses")
                        placeholder: ip.v4 ? "192.168.1.10/24" : "fd00::10/64"
                        validate: s => ip.v4 ? Net.ipv4Cidr(s) : Net.ipv6Cidr(s)
                        normalize: s => Net.withPrefix(s, ip.v4 ? 24 : 64)
                        onEdited: l => ed.setList(ip.fam + ".addresses", l)
                    }
                }
                NetRow {
                    visible: ip.method === "manual" || ed.list(ip.fam + ".addresses").length > 0
                    label: "Gateway"
                    changed: ed.changed(ip.fam + ".gateway")
                    Field {
                        key: ip.fam + ".gateway"
                        placeholderText: ip.v4 ? "192.168.1.1" : "fe80::1"
                        error: ed.val(key) !== "" && (ip.v4 ? Net.ipv4(ed.val(key)) : Net.ipv6(ed.val(key))) !== ""
                    }
                }
            }
        }

        // DHCP client options
        Reveal {
            open: ip.dhcp
            NetCard {
                Layout.fillWidth: true
                title: ip.v4 ? "DHCP client" : "DHCPv6 client"
                NetRow {
                    first: true
                    label: "Send hostname"
                    changed: ed.changed(ip.fam + ".dhcp-send-hostname")
                    Segmented {
                        small: true
                        options: [{ label: "Default", value: "-1" }, { label: "Yes", value: "1" }, { label: "No", value: "0" }]
                        value: ed.ternary(ip.fam + ".dhcp-send-hostname")
                        onEdited: v => ed.set(ip.fam + ".dhcp-send-hostname", v)
                    }
                }
                NetRow {
                    label: "Hostname to send"
                    desc: "Empty: this computer's hostname"
                    changed: ed.changed(ip.fam + ".dhcp-hostname")
                    Field { key: ip.fam + ".dhcp-hostname"; placeholderText: Network.hostname }
                }
                NetRow {
                    visible: ip.v4
                    label: "Client ID"
                    desc: "mac, perm-mac, duid, stable, ipv6-duid or hex bytes"
                    changed: ed.changed("ipv4.dhcp-client-id")
                    Field { key: "ipv4.dhcp-client-id"; placeholderText: "default" }
                }
                NetRow {
                    visible: !ip.v4
                    label: "DUID"
                    desc: "lease, llt, ll, stable-llt, stable-ll, stable-uuid or hex"
                    changed: ed.changed("ipv6.dhcp-duid")
                    Field { key: "ipv6.dhcp-duid"; placeholderText: "default" }
                }
                NetRow {
                    label: "Timeout"
                    desc: "Seconds to wait for a lease, 0 = default"
                    changed: ed.changed(ip.fam + ".dhcp-timeout")
                    Field { key: ip.fam + ".dhcp-timeout"; Layout.preferredWidth: 90 }
                }
                NetRow {
                    visible: ip.v4
                    wide: true
                    label: "Ignore these DHCP servers"
                    desc: "Offers from these addresses are refused (rogue DHCP)"
                    changed: ed.changed("ipv4.dhcp-reject-servers")
                    ListField {
                        Layout.fillWidth: true
                        values: ed.list("ipv4.dhcp-reject-servers")
                        placeholder: "Server address"
                        validate: Net.ipv4
                        onEdited: l => ed.setList("ipv4.dhcp-reject-servers", l)
                    }
                }
            }
        }

        // sharing = NetworkManager's DHCP server (dnsmasq)
        Reveal {
            open: ip.v4 && ip.method === "shared"
            NetCard {
                Layout.fillWidth: true
                title: "DHCP server (sharing)"
                icon: "󰒍"
                NetRow {
                    first: true
                    label: "Address range"
                    desc: "First and last address handed out, e.g. 10.42.0.10,10.42.0.200. Empty: the whole subnet"
                    changed: ed.changed("ipv4.shared-dhcp-range")
                    Field { key: "ipv4.shared-dhcp-range"; placeholderText: "automatic" }
                }
                NetRow {
                    label: "Lease time"
                    desc: "Seconds, 0 = default (1 h)"
                    changed: ed.changed("ipv4.shared-dhcp-lease-time")
                    Field { key: "ipv4.shared-dhcp-lease-time"; Layout.preferredWidth: 90 }
                }
            }
        }

        NetCard {
            Layout.fillWidth: true
            visible: !["disabled", "ignore"].includes(ip.method)
            title: "DNS"
            icon: "󰇖"
            NetRow {
                first: true
                wide: true
                label: "Servers"
                desc: ip.dhcp && !ed.yes(ip.fam + ".ignore-auto-dns") ? "Used before the ones from DHCP" : ""
                changed: ed.changed(ip.fam + ".dns")
                ListField {
                    Layout.fillWidth: true
                    values: ed.list(ip.fam + ".dns")
                    placeholder: ip.v4 ? "Add a DNS server" : "Add an IPv6 DNS server"
                    validate: ip.v4 ? Net.ipv4 : Net.ipv6
                    presets: ip.v4 ? ed.dnsPresets4 : ed.dnsPresets6
                    onEdited: l => ed.setList(ip.fam + ".dns", l)
                }
            }
            NetRow {
                visible: ip.dhcp
                label: "Ignore DNS from DHCP"
                desc: "Use only the servers above"
                changed: ed.changed(ip.fam + ".ignore-auto-dns")
                Toggle { key: ip.fam + ".ignore-auto-dns" }
            }
            NetRow {
                wide: true
                label: "Search domains"
                desc: "Short names like \"nas\" are tried with these"
                changed: ed.changed(ip.fam + ".dns-search")
                ListField {
                    Layout.fillWidth: true
                    values: ed.list(ip.fam + ".dns-search")
                    placeholder: "corp.example.com"
                    validate: s => Net.domain(s.replace(/^~/, ""))
                    onEdited: l => ed.setList(ip.fam + ".dns-search", l)
                }
            }
            NetRow {
                label: "Priority"
                desc: "Lower wins across connections; negative = only these servers"
                changed: ed.changed(ip.fam + ".dns-priority")
                Field { key: ip.fam + ".dns-priority"; Layout.preferredWidth: 90 }
            }
            NetRow {
                wide: true
                label: "Resolver options"
                desc: "e.g. rotate, timeout:1, edns0"
                changed: ed.changed(ip.fam + ".dns-options")
                ListField {
                    Layout.fillWidth: true
                    values: ed.list(ip.fam + ".dns-options")
                    placeholder: "Add an option"
                    onEdited: l => ed.setList(ip.fam + ".dns-options", l)
                }
            }
        }

        NetCard {
            Layout.fillWidth: true
            visible: !["disabled", "ignore"].includes(ip.method)
            title: "Routing"
            icon: "󰑪"
            NetRow {
                first: true
                wide: true
                label: "Static routes"
                desc: "destination [next hop] [metric], e.g. " + (ip.v4 ? "10.0.0.0/8 192.168.1.254 100" : "fd00:1::/64 fe80::1")
                changed: ed.changed(ip.fam + ".routes")
                ListField {
                    Layout.fillWidth: true
                    values: ed.list(ip.fam + ".routes")
                    placeholder: ip.v4 ? "10.0.0.0/8 192.168.1.254" : "fd00:1::/64 fe80::1"
                    separators: /[,;]+/
                    validate: ip.v4 ? Net.route4 : Net.route6
                    onEdited: l => ed.setList(ip.fam + ".routes", l)
                }
            }
            NetRow {
                visible: ip.dhcp
                label: "Ignore routes from DHCP"
                changed: ed.changed(ip.fam + ".ignore-auto-routes")
                Toggle { key: ip.fam + ".ignore-auto-routes" }
            }
            NetRow {
                label: "Never use as default route"
                desc: "Only reach its own networks through it (VPNs, lab / management networks)"
                changed: ed.changed(ip.fam + ".never-default")
                Toggle { key: ip.fam + ".never-default" }
            }
            NetRow {
                label: "Route metric"
                desc: "Lower is preferred, -1 = default"
                changed: ed.changed(ip.fam + ".route-metric")
                Field { key: ip.fam + ".route-metric"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "Required"
                desc: "The connection only counts as up once " + (ip.v4 ? "IPv4" : "IPv6") + " works"
                changed: ed.changed(ip.fam + ".may-fail")
                Toggle { key: ip.fam + ".may-fail"; invert: true }
            }
        }

        NetCard {
            Layout.fillWidth: true
            visible: !ip.v4 && !["disabled", "ignore"].includes(ip.method)
            title: "Privacy"
            NetRow {
                first: true
                label: "Temporary addresses"
                desc: "RFC 4941 privacy extensions"
                changed: ed.changed("ipv6.ip6-privacy")
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "-1" }, { label: "Off", value: "0" }, { label: "Prefer public", value: "1" }, { label: "Prefer temporary", value: "2" }]
                    value: ed.ternary("ipv6.ip6-privacy", ["disabled", "enabled-prefer-public-addr", "enabled-prefer-temp-addr"])
                    onEdited: v => ed.set("ipv6.ip6-privacy", v)
                }
            }
            NetRow {
                label: "Address generation"
                changed: ed.changed("ipv6.addr-gen-mode")
                Segmented {
                    small: true
                    options: [{ label: "Stable privacy", value: "stable-privacy" }, { label: "EUI-64 (from MAC)", value: "eui64" }, { label: "Default", value: "default" }]
                    value: ed.val("ipv6.addr-gen-mode")
                    onEdited: v => ed.set("ipv6.addr-gen-mode", v)
                }
            }
        }
    }

    IpPane { fam: "ipv4" }
    IpPane { fam: "ipv6" }

    // ── Link ────────────────────────────────────────────────────────────────
    component MacRow: NetRow {
        id: macRow
        required property string key
        label: "MAC address"
        desc: "What the network sees: the real one, a random one per connection, …"
        changed: ed.changed(key)
        readonly property string cur: ed.val(key)
        readonly property bool custom: /^([0-9a-fA-F]{2}:){5}/.test(cur)
        DropdownControl {
            implicitWidth: 170
            options: [{ label: "Default", value: "" }, { label: "Keep current", value: "preserve" },
                      { label: "Hardware", value: "permanent" }, { label: "Random", value: "random" },
                      { label: "Stable random", value: "stable" }, { label: "Custom…", value: "custom" }]
            value: macRow.custom ? "custom" : macRow.cur
            onEdited: v => ed.set(macRow.key, v === "custom" ? (Network.devices.find(d => d.name === ed.device)?.mac ?? "02:00:00:00:00:01") : v)
        }
        SearchField {
            visible: macRow.custom
            implicitWidth: 170
            implicitHeight: Properties.buttonHeight
            icon: ""
            clearable: false
            text: macRow.cur
            error: Net.mac(text) !== ""
            onEditingFinished: if (Net.mac(text) === "") ed.set(macRow.key, text)
        }
    }

    Pane {
        key: "link"

        // Ethernet
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "802-3-ethernet"
            title: "Ethernet"
            NetRow {
                first: true
                label: "MTU"
                desc: "auto or bytes (1500, 9000 for jumbo frames)"
                changed: ed.changed("802-3-ethernet.mtu")
                Field { key: "802-3-ethernet.mtu"; Layout.preferredWidth: 90 }
            }
            MacRow { key: "802-3-ethernet.cloned-mac-address" }
            NetRow {
                label: "Wake on LAN"
                changed: ed.changed("802-3-ethernet.wake-on-lan")
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "default" }, { label: "Off", value: "ignore" }, { label: "Magic packet", value: "magic" }]
                    value: ed.val("802-3-ethernet.wake-on-lan").replace(/ .*/, "") || "default"
                    onEdited: v => ed.set("802-3-ethernet.wake-on-lan", v)
                }
            }
            NetRow {
                label: "Auto-negotiate speed"
                changed: ed.changed("802-3-ethernet.auto-negotiate")
                Toggle { key: "802-3-ethernet.auto-negotiate" }
            }
            NetRow {
                sub: true
                visible: !ed.yes("802-3-ethernet.auto-negotiate")
                label: "Speed / duplex"
                desc: "Mb/s, e.g. 1000"
                changed: ed.changed("802-3-ethernet.speed") || ed.changed("802-3-ethernet.duplex")
                Field { key: "802-3-ethernet.speed"; Layout.preferredWidth: 90 }
                Segmented {
                    small: true
                    options: [{ label: "Full", value: "full" }, { label: "Half", value: "half" }]
                    value: ed.val("802-3-ethernet.duplex") || "full"
                    onEdited: v => ed.set("802-3-ethernet.duplex", v)
                }
            }
        }

        // Wi-Fi
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "802-11-wireless"
            title: "Wi-Fi"
            NetRow {
                first: true
                label: "Network name (SSID)"
                changed: ed.changed("802-11-wireless.ssid")
                Field { key: "802-11-wireless.ssid" }
            }
            NetRow {
                label: "Mode"
                desc: ed.val("802-11-wireless.mode") === "ap" ? "Hotspot: set IPv4 to Shared so others get addresses" : ""
                changed: ed.changed("802-11-wireless.mode")
                Segmented {
                    small: true
                    options: [{ label: "Client", value: "infrastructure" }, { label: "Hotspot", value: "ap" }, { label: "Ad-hoc", value: "adhoc" }]
                    value: ed.val("802-11-wireless.mode") || "infrastructure"
                    onEdited: v => ed.set("802-11-wireless.mode", v)
                }
            }
            NetRow {
                label: "Band"
                changed: ed.changed("802-11-wireless.band")
                Segmented {
                    small: true
                    options: [{ label: "Any", value: "" }, { label: "5 GHz", value: "a" }, { label: "2.4 GHz", value: "bg" }]
                    value: ed.val("802-11-wireless.band")
                    onEdited: v => ed.set("802-11-wireless.band", v)
                }
            }
            NetRow {
                label: "Access point (BSSID)"
                desc: "Lock to one access point, empty for any"
                changed: ed.changed("802-11-wireless.bssid")
                Field { key: "802-11-wireless.bssid"; placeholderText: "any" }
            }
            NetRow {
                label: "Hidden network"
                changed: ed.changed("802-11-wireless.hidden")
                Toggle { key: "802-11-wireless.hidden" }
            }
            MacRow { key: "802-11-wireless.cloned-mac-address" }
            NetRow {
                label: "MTU"
                changed: ed.changed("802-11-wireless.mtu")
                Field { key: "802-11-wireless.mtu"; Layout.preferredWidth: 90 }
            }
        }

        NetCard {
            id: secCard
            Layout.fillWidth: true
            visible: ed.type === "802-11-wireless"
            title: "Security"
            icon: "󰌾"
            readonly property string mgmt: "remove" in ed.edits ? "none" : ed.val("802-11-wireless-security.key-mgmt") || "none"
            NetRow {
                first: true
                wide: true
                label: "Security"
                changed: ed.changed("802-11-wireless-security.key-mgmt") || ("remove" in ed.edits)
                Segmented {
                    options: [{ label: "Open", value: "none" }, { label: "WPA/WPA2", value: "wpa-psk" }, { label: "WPA3", value: "sae" },
                              { label: "Enhanced Open", value: "owe" }, { label: "Enterprise", value: "wpa-eap" }]
                    value: secCard.mgmt
                    onEdited: v => {
                        const e = Object.assign({}, ed.edits)
                        delete e.remove
                        ed.edits = e
                        if (v === "none") {
                            if (ed.has("802-11-wireless-security")) { const e2 = Object.assign({}, ed.edits); e2.remove = "802-11-wireless-security"; delete e2["802-11-wireless-security.key-mgmt"]; ed.edits = e2 }
                        } else ed.set("802-11-wireless-security.key-mgmt", v)
                    }
                }
            }
            NetRow {
                visible: ["wpa-psk", "sae"].includes(ed.val("802-11-wireless-security.key-mgmt")) && !("remove" in ed.edits)
                label: "Password"
                changed: ed.changed("802-11-wireless-security.psk")
                SearchField {
                    id: psk
                    implicitWidth: 220
                    implicitHeight: Properties.buttonHeight
                    icon: ""
                    password: !reveal.shown
                    clearable: false
                    placeholderText: ed.raw("802-11-wireless-security.psk") === "<hidden>" ? "saved (hidden)" : "password"
                    text: ed.changed("802-11-wireless-security.psk") ? ed.val("802-11-wireless-security.psk") : (ed.secrets["802-11-wireless-security.psk"] ?? "")
                    onEditingFinished: if (text !== "" && text !== (ed.secrets["802-11-wireless-security.psk"] ?? "")) ed.set("802-11-wireless-security.psk", text)
                }
                IconButton {
                    id: reveal
                    property bool shown: false
                    icon: shown ? "󰈉" : "󰈈"
                    tooltip: shown ? "Hide" : "Show"
                    onClicked: {
                        shown = !shown
                        if (shown && ed.secrets["802-11-wireless-security.psk"] === undefined)
                            Network.secret(ed.uuid, "802-11-wireless-security.psk", v => {
                                const s = Object.assign({}, ed.secrets); s["802-11-wireless-security.psk"] = v; ed.secrets = s
                            })
                    }
                }
            }
            NetRow {
                visible: ed.val("802-11-wireless-security.key-mgmt") === "wpa-eap"
                label: "802.1X"
                desc: "EAP method, identity and certificates are in All settings (802-1x.*)"
                ActionButton { icon: "󰒓"; text: "All settings"; onClicked: ed.setTab("all") }
            }
        }

        // Bridge
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "bridge"
            title: "Bridge"
            NetRow {
                first: true
                label: "Spanning tree (STP)"
                changed: ed.changed("bridge.stp")
                Toggle { key: "bridge.stp" }
            }
            NetRow {
                sub: true
                visible: ed.yes("bridge.stp")
                label: "Priority"
                changed: ed.changed("bridge.priority")
                Field { key: "bridge.priority"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "Forward delay"
                desc: "Seconds"
                changed: ed.changed("bridge.forward-delay")
                Field { key: "bridge.forward-delay"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "VLAN filtering"
                changed: ed.changed("bridge.vlan-filtering")
                Toggle { key: "bridge.vlan-filtering" }
            }
            PortRow { portType: "bridge" }
        }

        // Bond
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "bond"
            title: "Bond"
            readonly property var opts: ed.val("bond.options").split(",").map(x => x.trim()).filter(x => x)
            NetRow {
                first: true
                label: "Mode"
                changed: ed.changed("bond.options")
                DropdownControl {
                    implicitWidth: 220
                    options: ["balance-rr", "active-backup", "balance-xor", "broadcast", "802.3ad", "balance-tlb", "balance-alb"]
                        .map(m => ({ label: m, value: m, hint: m === "802.3ad" ? "LACP" : m === "active-backup" ? "failover" : "" }))
                    value: (ed.val("bond.options").match(/mode=([^,\s]+)/) ?? [])[1] ?? "balance-rr"
                    onEdited: v => {
                        const o = ed.val("bond.options").split(",").map(x => x.trim()).filter(x => x && !x.startsWith("mode="))
                        ed.set("bond.options", ["mode=" + v].concat(o).join(","))
                    }
                }
            }
            NetRow {
                label: "Options"
                desc: "e.g. miimon=100, lacp_rate=fast"
                changed: ed.changed("bond.options")
                Field { key: "bond.options"; Layout.preferredWidth: 280 }
            }
            PortRow { portType: "bond" }
        }

        // VLAN
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "vlan"
            title: "VLAN"
            NetRow {
                first: true
                label: "Parent interface"
                changed: ed.changed("vlan.parent")
                DropdownControl {
                    implicitWidth: 200
                    options: Network.devices.filter(d => ["ethernet", "bond", "bridge"].includes(d.type)).map(d => ({ label: d.name, value: d.name }))
                    value: ed.val("vlan.parent")
                    onEdited: v => ed.set("vlan.parent", v)
                }
            }
            NetRow {
                label: "VLAN ID"
                desc: "1–4094"
                changed: ed.changed("vlan.id")
                Field { key: "vlan.id"; Layout.preferredWidth: 90 }
            }
        }

        // WireGuard
        NetCard {
            Layout.fillWidth: true
            visible: ed.type === "wireguard"
            title: "WireGuard"
            NetRow {
                first: true
                label: "Listen port"
                desc: "0 = random"
                changed: ed.changed("wireguard.listen-port")
                Field { key: "wireguard.listen-port"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "MTU"
                changed: ed.changed("wireguard.mtu")
                Field { key: "wireguard.mtu"; Layout.preferredWidth: 90 }
            }
            NetRow {
                label: "Peers & keys"
                desc: "Import a .conf on the Profiles tab, or edit wireguard.* in All settings"
                ActionButton { icon: "󰒓"; text: "All settings"; onClicked: ed.setTab("all") }
            }
        }
    }

    // add a port (bridge / bond member) from an interface
    component PortRow: NetRow {
        id: port
        required property string portType
        wide: true
        label: "Add a port"
        desc: "Creates a profile that puts an interface into this " + portType
        property string pick: ""
        RowLayout {
            spacing: 8
            DropdownControl {
                implicitWidth: 200
                options: Network.devices.filter(d => d.type === "ethernet" && d.managed).map(d => ({ label: d.name, value: d.name }))
                value: port.pick
                onEdited: v => port.pick = v
            }
            ActionButton {
                icon: "󰐕"
                text: "Add port"
                interactive: port.pick !== "" && ed.raw("connection.interface-name") !== ""
                onClicked: Network.add("ethernet", ed.raw("connection.id") + " port " + port.pick, port.pick,
                                       ["controller", ed.raw("connection.interface-name"), "port-type", port.portType])
            }
        }
    }

    // ── All settings ────────────────────────────────────────────────────────
    Pane {
        key: "all"
        id: allPane
        property string filter: ""
        readonly property var keys: Object.keys(ed.orig).filter(k => allPane.filter === "" || k.includes(allPane.filter.toLowerCase())
                                                                    || ed.val(k).toLowerCase().includes(allPane.filter.toLowerCase()))

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SearchField {
                Layout.fillWidth: true
                placeholderText: "Filter " + Object.keys(ed.orig).length + " settings (name or value)"
                onTextChanged: allPane.filter = text
            }
            Text {
                text: allPane.keys.length + " shown"
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: allCol.implicitHeight + 8
            radius: 14
            color: "#27000000"
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder

            Column {
                id: allCol
                y: 4
                width: parent.width
                Repeater {
                    // only render when the tab is open (180 rows)
                    model: ed.tab === "all" ? allPane.keys : []
                    Item {
                        id: prop
                        required property string modelData
                        required property int index
                        readonly property string section: modelData.split(".")[0]
                        readonly property bool newSection: index === 0 || allPane.keys[index - 1].split(".")[0] !== section
                        width: allCol.width
                        height: (newSection ? 28 : 0) + 36

                        Text {
                            visible: prop.newSection
                            x: 16
                            y: 10
                            text: prop.section
                            color: Colors.color6
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                        RowLayout {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 10 }
                            height: 36
                            spacing: 8
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: Colors.color6
                                opacity: ed.changed(prop.modelData) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            Text {
                                Layout.preferredWidth: Math.min(260, allCol.width * 0.42)
                                text: prop.modelData.slice(prop.section.length + 1)
                                color: Qt.rgba(1, 1, 1, ed.raw(prop.modelData) === "" && !ed.changed(prop.modelData) ? 0.45 : 0.85)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                                elide: Text.ElideMiddle
                            }
                            SearchField {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                icon: ""
                                clearable: false
                                font.pixelSize: 11
                                readonly property bool secret: ed.isSecret(prop.modelData)
                                password: secret && !ed.changed(prop.modelData)
                                placeholderText: secret ? "hidden, type to replace" : ""
                                text: secret && !ed.changed(prop.modelData) ? "" : ed.val(prop.modelData)
                                onEditingFinished: {
                                    if (secret && text === "") return
                                    if (text !== ed.val(prop.modelData)) ed.set(prop.modelData, text)
                                }
                            }
                            IconButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                iconSize: 12
                                icon: "󰑓"
                                tooltip: "Undo"
                                opacity: ed.changed(prop.modelData) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                onClicked: { const e = Object.assign({}, ed.edits); delete e[prop.modelData]; ed.edits = e }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Apply bar (in the window's footer, so it stays in reach) ────────────
    Rectangle {
        id: bar
        parent: ed.page?.footerHost ?? ed
        Layout.fillWidth: true
        Layout.preferredHeight: ed.visible && ed.changeCount > 0 ? barRow.implicitHeight + 22 : 0
        Layout.topMargin: Layout.preferredHeight > 0 ? 8 : 0
        visible: Layout.preferredHeight > 0.5
        clip: true
        radius: 14
        color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.12)
        border.width: Properties.panelBorderWidth
        border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4)
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        RowLayout {
            id: barRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 11 }
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: ed.changeCount + (ed.changeCount === 1 ? " change" : " changes") + " to " + (ed.val("connection.id") || "this profile")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: ed.problems.length > 0 ? "󰀦  " + ed.problems[0]
                        : ed.isActive && ed.page?.safeApply ? "Applied live, reverted after 20s unless you keep it"
                        : ed.isActive ? "Applied live to " + ed.device
                        : "Saved to the profile, used next time it connects"
                    color: ed.problems.length > 0 ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
            ActionButton {
                icon: "󰕌"
                text: "Discard"
                onClicked: ed.edits = {}
            }
            ActionButton {
                icon: Network.busy ? "󰔟" : "󰄬"
                text: "Apply"
                primary: true
                interactive: ed.problems.length === 0 && !Network.busy
                onClicked: ed.apply()
            }
        }
    }
}
