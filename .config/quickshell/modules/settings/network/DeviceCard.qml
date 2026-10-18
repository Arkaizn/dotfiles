import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "Net.js" as Net

// One interface on the network page. Collapsed: state, addresses, gateway,
// DNS and MAC (click a value to copy it). Expanded: the DHCP ↔ static switch
// (static is filled from the current lease), the DHCP lease, and actions.
Rectangle {
    id: card

    required property var device
    property var page                     // NetworkPage (applyChanges, openEditor, hide…)
    property bool expanded: false
    property bool isHidden: false         // shown anyway because "show hidden" is on

    readonly property var d: device
    readonly property bool connected: d.stateCode === 100
    readonly property bool connecting: d.stateCode > 30 && d.stateCode < 100
    readonly property bool managedHere: d.managed && !d.external && d.uuid !== ""
    readonly property color stateColor: connected ? Colors.color6
                                       : connecting ? Colors.yellow
                                       : d.stateCode <= 10 ? Colors.fade(0.3) : Colors.fade(0.5)

    // the profile, read when expanded (for the DHCP / static switch)
    property var profile: null
    property string draftMethod: ""       // "auto" | "manual" while editing, "" = untouched
    property string draftAddress: ""
    property string draftGateway: ""
    property var draftDns: []

    readonly property string method: profile?.settings["ipv4.method"] ?? ""
    // "Ignore DNS from DHCP" also ignores the DHCP search domain
    readonly property bool ignoresDhcpDns: (profile?.settings["ipv4.ignore-auto-dns"] ?? "") === "yes"
    readonly property var manualDomains: Net.splitList(profile?.settings["ipv4.dns-search"])
    // the search domains in use, each with where it comes from
    readonly property var domains: {
        const out = d.search4.map(x => ({ name: x, from: manualDomains.includes(x) ? "set by hand"
                                                        : x === d.dhcp?.domain ? "from DHCP " + (d.dhcp?.server ?? "") : "automatic" }))
        // set in the profile but not active (yet)
        for (const m of manualDomains) if (!d.search4.includes(m)) out.push({ name: m, from: "set by hand, not active" })
        return out
    }
    readonly property string shownMethod: draftMethod !== "" ? draftMethod : method
    readonly property bool dirty: draftMethod !== "" && (draftMethod !== method || draftMethod === "manual")

    function loadProfile() {
        if (!managedHere) { profile = null; return }
        Network.load(d.uuid, p => card.profile = p)
    }
    onExpandedChanged: if (expanded) loadProfile()
    Connections {
        target: Network
        function onDevicesChanged() { if (card.expanded && card.draftMethod === "") card.loadProfile() }
    }

    function pickMethod(m) {
        if (m === "manual") {
            // fill from the profile's static setup, else from what DHCP gave
            const s = profile?.settings ?? {}
            const addrs = Net.splitList(s["ipv4.addresses"])
            draftAddress = addrs[0] ?? d.ip4[0] ?? ""
            draftGateway = s["ipv4.gateway"] && s["ipv4.gateway"] !== "--" ? s["ipv4.gateway"] : d.gw4
            const dns = Net.splitList(s["ipv4.dns"])
            draftDns = dns.length > 0 ? dns : d.dns4.slice()
        }
        draftMethod = m === method && m !== "manual" ? "" : m
    }

    readonly property string addressError: draftMethod === "manual" ? Net.ipv4Cidr(draftAddress) : ""
    readonly property string gatewayError: draftMethod === "manual" && draftGateway !== "" ? Net.ipv4(draftGateway) : ""
    readonly property bool valid: addressError === "" && gatewayError === "" && draftDns.every(x => Net.ip(x) === "")

    function apply() {
        const s = profile.settings
        const changes = draftMethod === "manual"
            ? { "ipv4.method": "manual", "ipv4.addresses": Net.withPrefix(draftAddress, 24),
                "ipv4.gateway": draftGateway, "ipv4.dns": Net.joinList(draftDns) }
            : { "ipv4.method": "auto", "ipv4.addresses": "", "ipv4.gateway": "" }
        const old = {}
        for (const k of Object.keys(changes)) old[k] = s[k] === "--" ? "" : (s[k] ?? "")
        page.applyChanges(d.uuid, d.connection, connected ? d.name : "", changes, old, () => {
            card.draftMethod = ""
            card.loadProfile()
        })
    }

    component Info: Text { color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }

    implicitHeight: col.implicitHeight + 24
    radius: 14
    color: expanded ? Colors.fade(0.045) : hover.hovered ? Colors.fade(0.03) : Colors.card
    border.width: Properties.panelBorderWidth
    border.color: expanded ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.35) : Properties.cardBorder
    opacity: isHidden ? 0.6 : 1
    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }
    HoverHandler { id: hover }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
        spacing: 10

        // ── Header (click to expand) ──
        Item {
            Layout.fillWidth: true
            implicitHeight: head.implicitHeight

            RowLayout {
                id: head
                anchors { left: parent.left; right: parent.right }
                spacing: 12

                // type icon with a state ring that pulses while connecting
                Rectangle {
                    width: 38; height: 38; radius: 19
                    color: Qt.rgba(card.stateColor.r, card.stateColor.g, card.stateColor.b, 0.14)
                    border.width: 1.5
                    border.color: card.stateColor
                    Behavior on border.color { ColorAnimation { duration: 300 } }
                    Text {
                        anchors.centerIn: parent
                        text: Network.typeIcon(card.d.type)
                        color: card.connected ? Colors.color6 : Colors.fade(0.75)
                        font.pixelSize: 17
                        font.family: Properties.fontFamily
                    }
                    SequentialAnimation on opacity {
                        running: card.connecting
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    RowLayout {
                        spacing: 8
                        Text {
                            text: card.d.name
                            color: Colors.ink
                            font.pixelSize: 14
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                        Text {
                            visible: card.d.speed !== ""
                            text: card.d.speed
                            color: Colors.fade(0.4)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [card.d.connection || null, Network.typeLabel(card.d.type),
                               card.d.product ? (card.d.vendor + " " + card.d.product).trim() : null]
                              .filter(x => x).join("  ·  ")
                        color: Colors.fade(0.5)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                }

                // state pill
                Rectangle {
                    implicitWidth: stateText.implicitWidth + 18
                    implicitHeight: 22
                    radius: 11
                    color: Qt.rgba(card.stateColor.r, card.stateColor.g, card.stateColor.b, 0.14)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Text {
                        id: stateText
                        anchors.centerIn: parent
                        text: card.d.external ? "external" : card.d.state
                        color: card.connected ? Colors.color6 : Colors.fade(0.65)
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    text: "󰅀"
                    color: Colors.fade(0.5)
                    font.pixelSize: 14
                    font.family: Properties.fontFamily
                    rotation: card.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: card.expanded = !card.expanded
            }
        }

        // ── Addresses at a glance ──
        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: card.d.ip4.length + card.d.ip6.length > 0 || card.d.mac !== ""
            Repeater {
                model: card.d.ip4
                Chip { required property string modelData; label: "IPv4"; text: modelData; accent: true }
            }
            Chip { visible: card.d.gw4 !== ""; label: "GW"; text: card.d.gw4 }
            Repeater {
                model: card.d.dns4
                Chip { required property string modelData; label: "DNS"; text: modelData }
            }
            Repeater {
                model: card.expanded ? card.d.ip6 : card.d.ip6.slice(0, 1)
                Chip { required property string modelData; label: "IPv6"; text: modelData }
            }
            Repeater {
                model: card.d.search4
                Chip { required property string modelData; label: "DOMAIN"; text: modelData }
            }
            Chip { visible: card.d.mac !== "" && card.d.type !== "loopback"; label: "MAC"; text: card.d.mac }
        }

        // ── Expanded ──
        Reveal {
            open: card.expanded
            spacing: 10

            // not ours to configure
            Text {
                Layout.fillWidth: true
                visible: !card.managedHere
                text: !card.d.managed ? "NetworkManager doesn't manage this interface."
                    : card.d.external ? "Set up by another program (Docker, VPN client, VMware…); NetworkManager only watches it."
                    : "No profile is active on this interface."
                color: Colors.fade(0.55)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }

            // DHCP ↔ static
            Rectangle {
                Layout.fillWidth: true
                visible: card.managedHere && card.profile !== null && ["auto", "manual"].includes(card.method)
                implicitHeight: ipCol.implicitHeight + 24
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                border.color: card.dirty ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4) : Colors.fade(0.06)
                Behavior on border.color { ColorAnimation { duration: 200 } }

                ColumnLayout {
                    id: ipCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "IPv4 address"
                                color: Colors.ink
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                            Text {
                                text: card.shownMethod === "auto" ? "Assigned by the DHCP server" : "Set by hand"
                                color: Colors.fade(0.5)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                        }
                        Item { Layout.fillWidth: true }    // (text-only columns can't grow, this pushes the switch right)
                        Segmented {
                            options: [{ label: "DHCP", value: "auto", icon: "󰑓" }, { label: "Static", value: "manual", icon: "󰏫" }]
                            value: card.shownMethod
                            onEdited: v => card.pickMethod(v)
                        }
                    }

                    // static form
                    Reveal {
                        open: card.shownMethod === "manual"
                        spacing: 8
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Address / prefix"; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
                                SearchField {
                                    Layout.fillWidth: true
                                    implicitHeight: Properties.buttonHeight
                                    icon: ""
                                    clearable: false
                                    placeholderText: "192.168.1.10/24"
                                    text: card.draftMethod === "manual" ? card.draftAddress : (card.d.ip4[0] ?? "")
                                    error: card.addressError !== ""
                                    onTextEdited: { if (card.draftMethod !== "manual") card.pickMethod("manual"); card.draftAddress = text }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Gateway"; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
                                SearchField {
                                    Layout.fillWidth: true
                                    implicitHeight: Properties.buttonHeight
                                    icon: ""
                                    clearable: false
                                    placeholderText: "192.168.1.1 (optional)"
                                    text: card.draftMethod === "manual" ? card.draftGateway : card.d.gw4
                                    error: card.gatewayError !== ""
                                    onTextEdited: { if (card.draftMethod !== "manual") card.pickMethod("manual"); card.draftGateway = text }
                                }
                            }
                        }
                        Text { text: "DNS servers"; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
                        ListField {
                            Layout.fillWidth: true
                            values: card.draftMethod === "manual" ? card.draftDns : card.d.dns4
                            placeholder: "Add a DNS server"
                            validate: Net.ip
                            onEdited: list => { if (card.draftMethod !== "manual") card.pickMethod("manual"); card.draftDns = list }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: card.addressError !== "" || card.gatewayError !== ""
                            text: card.addressError !== "" ? "Address: " + card.addressError : "Gateway: " + card.gatewayError
                            color: Colors.red
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                    }

                    // DHCP lease
                    Reveal {
                        open: card.shownMethod === "auto" && card.d.dhcp !== null
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 6
                            Info { text: "DHCP server" }
                            Chip { text: card.d.dhcp?.server ?? "" }
                            Info { text: "Lease" }
                            Text {
                                text: {
                                    const l = card.d.dhcp
                                    if (!l) return ""
                                    const left = l.expiry - Network.now / 1000
                                    return Net.duration(l.leaseTime) + (l.expiry > 0 ? "  ·  renews / expires in " + Net.duration(left) : "")
                                }
                                color: Colors.ink
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                            Info { text: "DNS offered" }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: card.d.dhcp?.dns ?? []
                                    Chip { required property string modelData; text: modelData }
                                }
                                Text {
                                    visible: card.ignoresDhcpDns
                                    text: "ignored, this profile uses its own"
                                    color: Colors.yellow
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    topPadding: 5
                                }
                            }
                            Info { visible: (card.d.dhcp?.domain ?? "") !== ""; text: "Domain offered" }
                            Flow {
                                Layout.fillWidth: true
                                visible: (card.d.dhcp?.domain ?? "") !== ""
                                spacing: 6
                                Chip { text: card.d.dhcp?.domain ?? "" }
                                Text {
                                    visible: card.ignoresDhcpDns
                                    text: "ignored, this profile uses its own"
                                    color: Colors.yellow
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    topPadding: 5
                                }
                            }
                        }
                    }

                    // apply bar for the switch
                    Reveal {
                        open: card.dirty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: card.draftMethod === "auto" ? "Switch to DHCP (the static address is removed)"
                                    : card.method === "auto" ? "Filled in from the current lease, change what you need"
                                    : "Not applied yet"
                                color: Colors.fade(0.55)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                                wrapMode: Text.WordWrap
                            }
                            ActionButton {
                                icon: "󰕌"
                                text: "Undo"
                                onClicked: card.draftMethod = ""
                            }
                            ActionButton {
                                icon: Network.busy ? "󰔟" : "󰄬"
                                text: "Apply"
                                primary: true
                                interactive: card.valid && !Network.busy
                                onClicked: card.apply()
                            }
                        }
                    }
                }
            }

            // search domains in use and where they come from
            RowLayout {
                Layout.fillWidth: true
                visible: card.managedHere && card.profile !== null && card.domains.length > 0
                spacing: 10
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    text: "Search domain"
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: card.domains
                        Row {
                            required property var modelData
                            spacing: 6
                            Chip { text: modelData.name; accent: modelData.from.startsWith("set by hand") }
                            Text {
                                text: modelData.from
                                color: Colors.fade(0.45)
                                font.pixelSize: 10
                                font.family: Properties.fontFamily
                                topPadding: 5
                            }
                        }
                    }
                }
            }

            // other IPv4 methods: shown, changed in the profile editor
            Text {
                Layout.fillWidth: true
                visible: card.managedHere && card.profile !== null && !["auto", "manual"].includes(card.method)
                text: "IPv4 method: " + card.method + " (change it in the profile)"
                color: Colors.fade(0.55)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }

            // actions
            Flow {
                Layout.fillWidth: true
                spacing: 6
                ActionButton {
                    visible: card.managedHere && card.connected && card.method === "auto"
                    icon: "󰑓"
                    text: "Renew DHCP"
                    onClicked: Network.renew(card.d.name)
                }
                ActionButton {
                    visible: card.managedHere && card.connected
                    icon: "󰜉"
                    text: "Reconnect"
                    onClicked: Network.up(card.d.uuid, card.d.name, card.d.connection)
                }
                ActionButton {
                    visible: card.d.managed && !card.d.external && card.d.type !== "loopback"
                    icon: card.connected || card.connecting ? "󰌙" : "󰌘"
                    text: card.connected || card.connecting ? "Disconnect" : "Connect"
                    onClicked: card.connected || card.connecting ? Network.deviceDisconnect(card.d.name) : Network.deviceConnect(card.d.name)
                }
                ActionButton {
                    visible: card.managedHere
                    icon: "󰏫"
                    text: "Edit profile"
                    onClicked: card.page.openEditor(card.d.uuid)
                }
                ActionButton {
                    visible: !card.d.managed
                    icon: "󰒓"
                    text: "Let NetworkManager manage it"
                    onClicked: Network.setManaged(card.d.name, true)
                }
                ActionButton {
                    icon: card.isHidden ? "󰈈" : "󰈉"
                    text: card.isHidden ? "Always show" : "Hide"
                    onClicked: card.page.setHidden(card.d, !card.isHidden)
                }
            }
        }
    }
}
