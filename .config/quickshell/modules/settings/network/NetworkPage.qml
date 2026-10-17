import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "Net.js" as Net

// Network page of the settings app (NetworkManager, services/Network.qml).
//   Interfaces  every interface: state, addresses, DHCP ↔ static in one
//               click, DHCP lease, connect / renew / hide
//   Profiles    saved connections: new, import (VPN / WireGuard), duplicate,
//               delete, and the full editor (ProfileEditor)
//   DNS         global DNS override, resolvers in use, lookup test, hostname
//   Hosts       own /etc/hosts entries (remap a name to an IP on this computer)
// Changes to an active connection are applied live and reverted after 20s
// unless kept ("safe apply", can be turned off), so a typo can't lock you out.
ColumnLayout {
    id: netPage

    property Item footerHost: null       // the settings window's footer (apply bars)
    property string tab: "interfaces"
    property string editing: ""          // uuid open in the editor
    property bool showHidden: false

    spacing: 14

    Component.onCompleted: {
        Network.watchers++
        Network.refresh()
        Network.readHosts()
        sync(deviceModel, deviceOrder, "name")
        sync(profileModel, profileOrder, "uuid")
    }
    Component.onDestruction: Network.watchers--

    // ── Preferences (settings.json → "network") ─────────────────────────────
    readonly property var prefs: Settings.network
    readonly property bool safeApply: prefs.safeApply ?? true
    readonly property bool hideVirtual: prefs.hideVirtual ?? true
    readonly property var showList: prefs.showDevices ?? []
    readonly property var hideList: prefs.hideDevices ?? []

    function isVirtual(d) { return d.software || d.sysVirtual || d.type === "loopback" }
    function isHidden(d) { return hideList.includes(d.name) || (hideVirtual && isVirtual(d) && !showList.includes(d.name)) }

    function setHidden(d, hide) {
        const show = showList.filter(n => n !== d.name)
        const hid = hideList.filter(n => n !== d.name)
        if (hide) { if (!(hideVirtual && isVirtual(d))) hid.push(d.name) }
        else if (hideVirtual && isVirtual(d)) show.push(d.name)
        Settings.set("network", "showDevices", show)
        Settings.set("network", "hideDevices", hid)
        Network.say(hide ? d.name + " hidden" : d.name + " always shown")
    }

    // tabs slide in from the side they sit on: a tab to the right comes in
    // from the right, one to the left from the left
    readonly property var tabOrder: ["interfaces", "profiles", "dns", "hosts"]
    property int tabDir: 1
    function setTab(t) {
        if (t === tab) return
        tabDir = tabOrder.indexOf(t) > tabOrder.indexOf(tab) ? 1 : -1
        tab = t
    }

    function openEditor(uuid) {
        setTab("profiles")
        netPage.editing = uuid
    }

    // with `device` the change goes live there; safe apply reverts it after 20s
    function applyChanges(uuid, name, device, changes, old, cb, allowSafe) {
        if (device !== "" && safeApply && allowSafe !== false && Network.pending === null) {
            Network.applySafely(uuid, name, device, changes, old, (ok, err) => {
                Network.say(ok ? "Applied to " + name + " — keep it below, or it's reverted" : err, !ok)
                if (cb) cb(ok)
            })
        } else {
            Network.modify(uuid, changes, device, (ok, err) => {
                Network.say(ok ? (device !== "" ? "Applied to " + name : "Saved " + name) : err, !ok)
                if (cb) cb(ok)
            })
        }
    }

    // ── Lists synced in place (delegates keep their state across refreshes) ─
    readonly property var deviceOrder: Network.devices.slice().sort((a, b) => {
        const rank = d => (d.stateCode === 100 && !netPage.isVirtual(d) ? 0 : !netPage.isVirtual(d) ? 1 : 2)
        return rank(a) - rank(b) || a.name.localeCompare(b.name)
    }).filter(d => netPage.showHidden || !netPage.isHidden(d))
    readonly property int hiddenCount: Network.devices.filter(d => netPage.isHidden(d)).length

    ListModel { id: deviceModel }
    ListModel { id: profileModel }

    function sync(model, items, key) {
        const keys = items.map(x => x[key])
        for (let i = model.count - 1; i >= 0; i--)
            if (!keys.includes(model.get(i).key)) model.remove(i)
        keys.forEach((k, i) => {
            let at = -1
            for (let j = 0; j < model.count; j++) if (model.get(j).key === k) { at = j; break }
            if (at < 0) model.insert(i, { key: k })
            else if (at !== i) model.move(at, i, 1)
        })
    }
    onDeviceOrderChanged: sync(deviceModel, deviceOrder, "name")
    onProfileOrderChanged: sync(profileModel, profileOrder, "uuid")

    // ── Top bar ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Segmented {
            options: [{ label: "Interfaces", value: "interfaces", icon: "󰈀" },
                      { label: "Profiles", value: "profiles", icon: "󰒓" },
                      { label: "DNS", value: "dns", icon: "󰇖" },
                      { label: "Hosts", value: "hosts", icon: "󰒋" }]
            value: netPage.tab
            onEdited: v => { netPage.setTab(v); if (v !== "profiles") netPage.editing = "" }
        }
        Item { Layout.fillWidth: true }
        // connectivity at a glance
        Rectangle {
            implicitWidth: connRow.implicitWidth + 18
            implicitHeight: 26
            radius: 13
            readonly property bool ok: Network.connectivity === "full"
            color: ok ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.14) : Qt.rgba(0.98, 0.89, 0.69, 0.14)
            RowLayout {
                id: connRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: parent.parent.ok ? Colors.color6 : "#f9e2af"
                }
                Text {
                    text: !Network.networking ? "Networking off"
                        : Network.connectivity === "full" ? "Online"
                        : Network.connectivity === "limited" ? "Limited"
                        : Network.connectivity === "portal" ? "Captive portal"
                        : Network.connectivity === "none" ? "Offline" : "…"
                    color: "white"
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
        }
        IconButton {
            id: refreshBtn
            icon: "󰑓"
            tooltip: "Refresh"
            onClicked: { spin.restart(); Network.refresh() }
            RotationAnimation on rotation { id: spin; running: false; from: 0; to: 360; duration: 600; easing.type: Easing.OutCubic }
        }
    }

    // ── Toast ───────────────────────────────────────────────────────────────
    Reveal {
        id: toast
        property var msg: null
        open: msg !== null
        Connections {
            target: Network
            function onMessageChanged() {
                toast.msg = Network.message
                if (Network.message && !Network.message.error) toastTimer.restart()
                else toastTimer.stop()
            }
        }
        Timer { id: toastTimer; interval: 4000; onTriggered: toast.msg = null }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: toastRow.implicitHeight + 16
            radius: 12
            readonly property color tint: toast.msg?.error ? Qt.rgba(0.95, 0.55, 0.66, 1) : Colors.color6
            color: Qt.rgba(tint.r, tint.g, tint.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.4)
            RowLayout {
                id: toastRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 6 }
                spacing: 8
                Text {
                    text: toast.msg?.error ? "󰀦" : "󰄬"
                    color: toast.msg?.error ? "#f38ba8" : Colors.color6
                    font.pixelSize: 15
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: toast.msg?.text ?? ""
                    color: "white"
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
                IconButton {
                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                    icon: "󰅖"
                    tooltip: "Dismiss"
                    onClicked: toast.msg = null
                }
            }
        }
    }

    // tab body that slides + fades in
    component TabView: ColumnLayout {
        id: tv
        property string key
        Layout.fillWidth: true
        spacing: 14
        visible: netPage.tab === key
        property real slide: 0
        transform: Translate { x: tv.slide }
        // started by the tab change itself: `visible` also flips when a parent
        // shows / hides, which used to start this (and nested slides) twice
        Connections {
            target: netPage
            function onTabChanged() { if (netPage.tab === tv.key) tvIn.restart() }
        }
        ParallelAnimation {
            id: tvIn
            NumberAnimation { target: tv; property: "opacity"; from: 0; to: 1; duration: 220 }
            NumberAnimation { target: tv; property: "slide"; from: 40 * netPage.tabDir; to: 0; duration: 300; easing.type: Easing.OutCubic }
        }
    }

    // a delegate that eases in when it appears
    component Appear: Item {
        id: ap
        opacity: 0
        property real lift: 10
        transform: Translate { y: ap.lift }
        Component.onCompleted: apIn.start()
        ParallelAnimation {
            id: apIn
            NumberAnimation { target: ap; property: "opacity"; to: 1; duration: 220 }
            NumberAnimation { target: ap; property: "lift"; to: 0; duration: 280; easing.type: Easing.OutCubic }
        }
    }

    // ── Interfaces ──────────────────────────────────────────────────────────
    TabView {
        key: "interfaces"

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: deviceModel.count + (deviceModel.count === 1 ? " interface" : " interfaces")
                      + (netPage.hiddenCount > 0 && !netPage.showHidden ? "  ·  " + netPage.hiddenCount + " hidden" : "")
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 12
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                text: "Hide virtual"
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
            ToggleSwitch {
                checked: netPage.hideVirtual
                onToggled: v => Settings.set("network", "hideVirtual", v)
            }
            ActionButton {
                visible: netPage.hiddenCount > 0
                icon: netPage.showHidden ? "󰈉" : "󰈈"
                text: netPage.showHidden ? "Hide them" : "Show hidden"
                onClicked: netPage.showHidden = !netPage.showHidden
            }
        }

        Text {
            Layout.fillWidth: true
            visible: netPage.hideVirtual
            text: "Virtual = Docker, bridges, veth, VMware / VirtualBox, tunnels, loopback. Hide or always show single ones from their card."
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 10
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: deviceModel
            Appear {
                required property string key
                readonly property var dev: Network.devices.find(d => d.name === key) ?? null
                Layout.fillWidth: true
                implicitHeight: card.implicitHeight
                visible: dev !== null
                DeviceCard {
                    id: card
                    width: parent.width
                    device: parent.dev ?? ({ name: "", type: "", mac: "", stateCode: 0, state: "", external: false, managed: false,
                                             uuid: "", connection: "", speed: "", vendor: "", product: "", ip4: [], ip6: [],
                                             dns4: [], gw4: "", dhcp: null })
                    page: netPage
                    isHidden: parent.dev ? netPage.isHidden(parent.dev) : false
                }
            }
        }

        // networking switches
        NetCard {
            Layout.fillWidth: true
            Layout.topMargin: 6
            title: "Switches"
            NetRow {
                first: true
                label: "Networking"
                desc: "Everything NetworkManager handles, off = offline"
                ToggleSwitch { checked: Network.networking; onToggled: v => Network.setNetworking(v) }
            }
            NetRow {
                visible: Network.wifiHardware || Network.devices.some(d => d.type === "wifi")
                label: "Wi-Fi"
                ToggleSwitch { checked: Network.wifiEnabled; onToggled: v => Network.setWifi(v) }
            }
            NetRow {
                label: "Safe apply"
                desc: "Changes to an active connection revert after 20s unless you keep them"
                ToggleSwitch { checked: netPage.safeApply; onToggled: v => Settings.set("network", "safeApply", v) }
            }
        }
    }

    // ── Profiles ────────────────────────────────────────────────────────────
    property string profileFilter: ""
    readonly property var profileOrder: Network.connections.filter(c => {
        if (c.type === "loopback") return netPage.showHidden
        const dev = Network.devices.find(d => d.name === c.device)
        if (dev && netPage.isHidden(dev) && !netPage.showHidden) return false
        const q = netPage.profileFilter.toLowerCase()
        return q === "" || (c.name + " " + c.type + " " + c.device).toLowerCase().includes(q)
    }).sort((a, b) => (b.active - a.active) || a.type.localeCompare(b.type) || a.name.localeCompare(b.name))

    TabView {
        key: "profiles"

        // list ↔ editor (drill-in)
        ColumnLayout {
            id: profileList
            Layout.fillWidth: true
            spacing: 14
            visible: netPage.editing === ""
            property real slide: 0
            transform: Translate { x: profileList.slide }
            // only when coming back from the editor (not when the tab itself slides in)
            Connections {
                target: netPage
                function onEditingChanged() { if (netPage.editing === "") listIn.restart() }
            }
            ParallelAnimation {
                id: listIn
                NumberAnimation { target: profileList; property: "opacity"; from: 0; to: 1; duration: 220 }
                NumberAnimation { target: profileList; property: "slide"; from: -40; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SearchField {
                    Layout.fillWidth: true
                    placeholderText: "Filter profiles"
                    onTextChanged: netPage.profileFilter = text
                }
                ActionButton {
                    icon: newPanel.open ? "󰅖" : "󰐕"
                    text: "New"
                    primary: newPanel.open
                    onClicked: newPanel.open = !newPanel.open
                }
                ActionButton {
                    icon: "󰋺"
                    text: "Import"
                    onClicked: importPick.running = true
                }
            }

            // new profile
            Reveal {
                id: newPanel
                property string type: "ethernet"
                property string name: ""
                property string ifname: ""
                property string ssid: ""
                property string vlanParent: ""
                property string vlanId: "10"
                readonly property var types: [
                    { label: "Ethernet", value: "ethernet", icon: "󰈀" }, { label: "Wi-Fi", value: "wifi", icon: "󰖩" },
                    { label: "Bridge", value: "bridge", icon: "󰌘" }, { label: "Bond", value: "bond", icon: "󰌷" },
                    { label: "VLAN", value: "vlan", icon: "󰛳" }, { label: "WireGuard", value: "wireguard", icon: "󰒃" }]
                readonly property bool needsIfname: ["bridge", "bond", "wireguard", "vlan"].includes(type)
                readonly property string defaultIf: ({ bridge: "br0", bond: "bond0", wireguard: "wg0",
                                                      vlan: (vlanParent || "eth0") + "." + vlanId })[type] ?? ""
                readonly property string problem: name.trim() === "" ? "Give it a name"
                    : type === "wifi" && ssid.trim() === "" ? "Wi-Fi needs a network name (SSID)"
                    : type === "vlan" && (vlanParent === "" || !(parseInt(vlanId) >= 1 && parseInt(vlanId) <= 4094)) ? "VLAN needs a parent and an ID 1–4094"
                    : ""
                onOpenChanged: if (open) name = ""

                function create() {
                    const ifn = ifname !== "" ? ifname : needsIfname ? defaultIf : ""
                    const extra = type === "wifi" ? ["ssid", ssid]
                                : type === "vlan" ? ["dev", vlanParent, "id", vlanId]
                                : type === "bond" ? ["bond.options", "mode=active-backup"] : []
                    Network.add(type, name.trim(), ifn, extra, uuid => {
                        if (uuid === "") return
                        newPanel.open = false
                        netPage.openEditor(uuid)
                    })
                }

                NetCard {
                    Layout.fillWidth: true
                    title: "New profile"
                    icon: "󰐕"
                    NetRow {
                        first: true
                        wide: true
                        label: "Type"
                        Segmented {
                            options: newPanel.types
                            value: newPanel.type
                            onEdited: v => { newPanel.type = v; newPanel.ifname = "" }
                        }
                    }
                    NetRow {
                        label: "Name"
                        SearchField {
                            implicitWidth: 240
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            placeholderText: newPanel.types.find(t => t.value === newPanel.type).label + " profile"
                            text: newPanel.name
                            onTextEdited: newPanel.name = text
                        }
                    }
                    NetRow {
                        visible: ["ethernet", "wifi"].includes(newPanel.type)
                        label: "Interface"
                        desc: "Empty: any matching interface"
                        DropdownControl {
                            implicitWidth: 240
                            options: [{ label: "Any", value: "" }].concat(Network.devices
                                .filter(d => d.type === (newPanel.type === "wifi" ? "wifi" : "ethernet") && !netPage.isVirtual(d))
                                .map(d => ({ label: d.name, value: d.name })))
                            value: newPanel.ifname
                            onEdited: v => newPanel.ifname = v
                        }
                    }
                    NetRow {
                        visible: newPanel.type === "wifi"
                        label: "Network name (SSID)"
                        SearchField {
                            implicitWidth: 240
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            text: newPanel.ssid
                            onTextEdited: newPanel.ssid = text
                        }
                    }
                    NetRow {
                        visible: newPanel.type === "vlan"
                        label: "Parent / ID"
                        DropdownControl {
                            implicitWidth: 160
                            options: Network.devices.filter(d => ["ethernet", "bond", "bridge"].includes(d.type) && !netPage.isVirtual(d))
                                .map(d => ({ label: d.name, value: d.name }))
                            value: newPanel.vlanParent
                            onEdited: v => newPanel.vlanParent = v
                        }
                        SearchField {
                            implicitWidth: 80
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            clearable: false
                            text: newPanel.vlanId
                            onTextEdited: newPanel.vlanId = text
                        }
                    }
                    NetRow {
                        visible: newPanel.needsIfname
                        label: "Interface name"
                        desc: "The new interface"
                        SearchField {
                            implicitWidth: 160
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            clearable: false
                            placeholderText: newPanel.defaultIf
                            text: newPanel.ifname
                            onTextEdited: newPanel.ifname = text
                        }
                    }
                    NetRow {
                        Text {
                            text: newPanel.problem
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                        ActionButton {
                            icon: "󰄬"
                            text: "Create & edit"
                            primary: true
                            interactive: newPanel.problem === "" && !Network.busy
                            onClicked: newPanel.create()
                        }
                    }
                }
            }

            // the profiles
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: profCol.implicitHeight + 8
                radius: 14
                color: "#27000000"
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder

                ColumnLayout {
                    id: profCol
                    y: 4
                    width: parent.width
                    spacing: 0
                    Repeater {
                        model: profileModel
                        Appear {
                            id: prow
                            required property string key
                            required property int index
                            readonly property var c: Network.connections.find(x => x.uuid === key) ?? null
                            Layout.fillWidth: true
                            implicitHeight: 54
                            visible: c !== null
                            property bool armed: false

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                radius: 10
                                color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Rectangle {
                                visible: prow.index > 0
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.06)
                            }
                            HoverHandler { id: rowHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: netPage.openEditor(prow.key)
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                                spacing: 12
                                Rectangle {
                                    width: 32; height: 32; radius: 16
                                    color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, prow.c?.active ? 0.18 : 0.05)
                                    border.width: 1.5
                                    border.color: prow.c?.active ? Colors.color6 : Qt.rgba(1, 1, 1, 0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: Network.typeIcon(prow.c?.type ?? "")
                                        color: prow.c?.active ? Colors.color6 : Qt.rgba(1, 1, 1, 0.65)
                                        font.pixelSize: 14
                                        font.family: Properties.fontFamily
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: prow.c?.name ?? ""
                                        color: "white"
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            const c = prow.c
                                            if (!c) return ""
                                            const ago = c.timestamp > 0 ? Net.duration(Date.now() / 1000 - c.timestamp) + " ago" : "never used"
                                            return [Network.typeLabel(c.type), c.active ? "active on " + c.device : ago,
                                                    c.autoconnect ? null : "manual"].filter(x => x).join("  ·  ")
                                        }
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: 11
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }
                                // quick actions, fade in on hover
                                RowLayout {
                                    spacing: 4
                                    opacity: rowHover.hovered || prow.armed ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    IconButton {
                                        icon: prow.c?.active ? "󰌙" : "󰌘"
                                        tooltip: prow.c?.active ? "Disconnect" : "Connect"
                                        onClicked: prow.c.active ? Network.down(prow.key, prow.c.name) : Network.up(prow.key, "", prow.c.name)
                                    }
                                    IconButton {
                                        icon: "󰆏"
                                        tooltip: "Duplicate"
                                        onClicked: Network.clone(prow.key, prow.c.name + " (copy)")
                                    }
                                    IconButton {
                                        icon: "󰆴"
                                        tooltip: prow.armed ? "Click again to delete" : "Delete"
                                        active: prow.armed
                                        textColor: "#f38ba8"
                                        onClicked: {
                                            if (!prow.armed) { prow.armed = true; disarmP.restart(); return }
                                            Network.remove(prow.key, prow.c.name)
                                        }
                                        Timer { id: disarmP; interval: 3000; onTriggered: prow.armed = false }
                                    }
                                }
                                Rectangle {
                                    visible: prow.c?.active ?? false
                                    implicitWidth: actText.implicitWidth + 16
                                    implicitHeight: 20
                                    radius: 10
                                    color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.14)
                                    Text {
                                        id: actText
                                        anchors.centerIn: parent
                                        text: "active"
                                        color: Colors.color6
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                }
                                Text {
                                    text: "󰅂"
                                    color: Qt.rgba(1, 1, 1, rowHover.hovered ? 0.7 : 0.3)
                                    font.pixelSize: 14
                                    font.family: Properties.fontFamily
                                }
                            }
                        }
                    }
                    Text {
                        Layout.margins: 16
                        visible: profileModel.count === 0
                        text: netPage.profileFilter !== "" ? "No profile matches" : "No profiles"
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                    }
                }
            }
        }

        Loader {
            id: editorLoader
            Layout.fillWidth: true
            active: netPage.editing !== ""
            visible: active
            property real slide: 0
            transform: Translate { x: editorLoader.slide }
            onLoaded: edIn.restart()
            ParallelAnimation {
                id: edIn
                NumberAnimation { target: editorLoader; property: "opacity"; from: 0; to: 1; duration: 220 }
                NumberAnimation { target: editorLoader; property: "slide"; from: 40; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
            sourceComponent: ProfileEditor {
                uuid: netPage.editing
                page: netPage
                onBack: netPage.editing = ""
            }
        }
    }

    // VPN / WireGuard import: pick a file, the type follows from it
    Process {
        id: importPick
        command: ["zenity", "--file-selection", "--title=Import a VPN or WireGuard profile",
                  "--file-filter=VPN / WireGuard | *.ovpn *.conf *.pcf *.vpnc", "--file-filter=All files | *"]
        stdout: StdioCollector { id: importOut }
        onExited: code => {
            const f = importOut.text.trim()
            if (code !== 0 || f === "") return
            // a WireGuard .conf has [Interface] + PrivateKey; anything else is tried as OpenVPN
            Network.run(["grep", "-qi", "^\\s*PrivateKey", f], c =>
                Network.importFile(c === 0 ? "wireguard" : "openvpn", f))
        }
    }

    // ── DNS & host ──────────────────────────────────────────────────────────
    TabView {
        key: "dns"

        NetCard {
            id: globalCard
            Layout.fillWidth: true
            title: "Global DNS"
            icon: "󰇖"
            readonly property bool isOn: Network.globalDns.servers.length > 0
            property var servers: []
            property var searches: []
            property bool dirty: false
            function reset() { servers = Network.globalDns.servers.slice(); searches = Network.globalDns.searches.slice(); dirty = false }
            Component.onCompleted: reset()
            Connections {
                target: Network
                function onGlobalDnsChanged() { if (!globalCard.dirty) globalCard.reset() }
            }
            tint: isOn ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08) : "transparent"

            NetRow {
                first: true
                label: globalCard.isOn ? "On — overrides every network" : "Off — each network uses its own DNS"
                desc: "Set per network in a profile's IPv4 / IPv6 tab. Changing this asks for your password."
                Rectangle {
                    implicitWidth: gs.implicitWidth + 18
                    implicitHeight: 22
                    radius: 11
                    color: globalCard.isOn ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18) : Qt.rgba(1, 1, 1, 0.07)
                    Text {
                        id: gs
                        anchors.centerIn: parent
                        text: globalCard.isOn ? "global" : "per network"
                        color: globalCard.isOn ? Colors.color6 : Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                }
            }
            NetRow {
                wide: true
                label: "Servers"
                changed: globalCard.dirty
                ListField {
                    Layout.fillWidth: true
                    values: globalCard.servers
                    placeholder: "Add a DNS server (IPv4 or IPv6)"
                    validate: Net.ip
                    presets: [{ label: "Cloudflare", values: ["1.1.1.1", "1.0.0.1"] }, { label: "Quad9", values: ["9.9.9.9", "149.112.112.112"] },
                              { label: "Google", values: ["8.8.8.8", "8.8.4.4"] }, { label: "AdGuard", values: ["94.140.14.14", "94.140.15.15"] }]
                    onEdited: l => { globalCard.servers = l; globalCard.dirty = true }
                }
            }
            NetRow {
                wide: true
                label: "Search domains"
                ListField {
                    Layout.fillWidth: true
                    values: globalCard.searches
                    placeholder: "corp.example.com"
                    validate: Net.domain
                    onEdited: l => { globalCard.searches = l; globalCard.dirty = true }
                }
            }
            NetRow {
                ActionButton {
                    visible: globalCard.isOn
                    icon: "󰅖"
                    text: "Turn off"
                    onClicked: { Network.setGlobalDns([], []); globalCard.dirty = false }
                }
                ActionButton {
                    visible: globalCard.dirty
                    icon: "󰕌"
                    text: "Undo"
                    onClicked: globalCard.reset()
                }
                ActionButton {
                    icon: "󰌾"
                    text: globalCard.isOn ? "Update" : "Use for all networks"
                    primary: globalCard.dirty
                    interactive: globalCard.dirty && globalCard.servers.length > 0
                    onClicked: { Network.setGlobalDns(globalCard.servers, globalCard.searches); globalCard.dirty = false }
                }
            }
        }

        NetCard {
            Layout.fillWidth: true
            title: "Resolvers in use"
            icon: "󰒍"
            Repeater {
                model: Network.resolved.filter(r => r.servers.length > 0 || r.link === "Global")
                    .filter(r => { const d = Network.devices.find(x => x.name === r.link); return !d || netPage.showHidden || !netPage.isHidden(d) })
                NetRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    label: modelData.link
                    desc: modelData.link === "Global" ? "Used for everything not tied to a network" : ""
                    Flow {
                        Layout.maximumWidth: 360
                        spacing: 6
                        layoutDirection: Qt.RightToLeft
                        Repeater {
                            // reversed: right-to-left would flip the order, which matters for DNS
                            model: modelData.servers.slice().reverse()
                            Chip { required property string modelData; text: modelData }
                        }
                        Text {
                            visible: modelData.servers.length === 0
                            text: "none"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                    }
                }
            }
        }

        NetCard {
            id: lookupCard
            Layout.fillWidth: true
            title: "Lookup"
            icon: "󰍉"
            property string result: ""
            property bool ok: true
            property bool running: false
            function go(name) {
                if (name.trim() === "") return
                running = true
                Network.lookup(name.trim(), (ok, text) => { lookupCard.running = false; lookupCard.ok = ok; lookupCard.result = text })
            }
            NetRow {
                first: true
                wide: true
                label: "Test a name"
                desc: "Asks systemd-resolved, like apps do"
                ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SearchField {
                        id: lookupField
                        Layout.fillWidth: true
                        placeholderText: "example.com"
                        onAccepted: lookupCard.go(text)
                    }
                    ActionButton {
                        icon: lookupCard.running ? "󰔟" : "󰍉"
                        text: "Look up"
                        primary: true
                        interactive: lookupField.text !== "" && !lookupCard.running
                        onClicked: lookupCard.go(lookupField.text)
                    }
                    ActionButton {
                        icon: "󰃢"
                        text: "Flush cache"
                        onClicked: Network.flushDns()
                    }
                }
                Reveal {
                    open: lookupCard.result !== ""
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: resText.implicitHeight + 16
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.25)
                        Text {
                            id: resText
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                            text: lookupCard.result
                            color: lookupCard.ok ? "white" : "#f38ba8"
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                        }
                    }
                }
                }
            }
        }

        NetCard {
            Layout.fillWidth: true
            title: "Host"
            icon: "󰒋"
            NetRow {
                first: true
                label: "Hostname"
                desc: "Sent to DHCP servers, shown on the network. Asks for your password."
                SearchField {
                    id: hostField
                    implicitWidth: 200
                    implicitHeight: Properties.buttonHeight
                    icon: ""
                    clearable: false
                    text: Network.hostname
                    onAccepted: if (text !== Network.hostname && Net.domain(text) === "") Network.setHostname(text)
                }
                ActionButton {
                    icon: "󰌾"
                    text: "Set"
                    interactive: hostField.text !== Network.hostname && Net.domain(hostField.text) === ""
                    onClicked: Network.setHostname(hostField.text)
                }
            }
        }
    }

    // ── Hosts file ──────────────────────────────────────────────────────────
    TabView {
        id: hostsTab
        key: "hosts"

        // editable copy of Settings.network.hosts until Apply
        property var draft: []
        property bool dirty: false
        function load() { draft = JSON.parse(JSON.stringify(Settings.network.hosts ?? [])); dirty = false }
        function change(list) { draft = list; dirty = true }
        function update(id, patch) { change(draft.map(e => e.id === id ? Object.assign({}, e, patch) : e)) }
        Component.onCompleted: load()

        function problem(e) {
            if (Net.ip(e.ip ?? "") !== "") return "IP: " + Net.ip(e.ip ?? "")
            const names = (e.names ?? "").trim().split(/\s+/).filter(x => x)
            if (names.length === 0) return "needs a name"
            for (const n of names) if (Net.domain(n) !== "") return "\"" + n + "\" isn't a valid name"
            return ""
        }
        readonly property bool valid: draft.every(e => problem(e) === "")
        // what's in /etc/hosts now vs. what's saved
        readonly property bool inSync: {
            const want = (Settings.network.hosts ?? []).filter(e => e.enabled !== false).map(e => e.ip + " " + e.names.trim().split(/\s+/).join(" "))
            const have = Network.hostsActive.map(e => e.ip + " " + e.names)
            return want.length === have.length && want.every((w, i) => w === have[i])
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            text: "Like the hosts file on Windows: these names resolve to the IP you set, only on this computer (/etc/hosts). "
                  + "Browsers with secure DNS (DNS over HTTPS) can skip it."
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        NetCard {
            id: hostsCard
            Layout.fillWidth: true
            title: "Your entries" + (hostsTab.draft.length > 0 ? "  ·  " + hostsTab.draft.length : "")
            icon: "󰒋"
            header: [
                Text {
                    visible: !hostsTab.dirty
                    text: hostsTab.inSync ? "in /etc/hosts" : "not applied"
                    color: hostsTab.inSync ? Colors.color6 : "#f9e2af"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Properties.fontFamily
                }
            ]

            Repeater {
                model: hostsTab.draft
                ColumnLayout {
                    id: hrow
                    required property var modelData
                    required property int index
                    readonly property var e: modelData
                    readonly property string err: hostsTab.problem(e)
                    property string testResult: ""
                    property bool testOk: true
                    Layout.fillWidth: true
                    spacing: 0
                    NetRow {
                        first: hrow.index === 0
                        opacity: hrow.e.enabled === false ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        SearchField {
                            implicitWidth: 150
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            clearable: false
                            placeholderText: "192.168.0.5"
                            text: hrow.e.ip ?? ""
                            error: (hrow.e.ip ?? "") !== "" && Net.ip(hrow.e.ip) !== ""
                            onEditingFinished: if (text.trim() !== hrow.e.ip) hostsTab.update(hrow.e.id, { ip: text.trim() })
                        }
                        Text { text: "→"; color: Qt.rgba(1, 1, 1, 0.4); font.pixelSize: 13; font.family: Properties.fontFamily }
                        SearchField {
                            Layout.fillWidth: true
                            implicitWidth: 240
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            clearable: false
                            placeholderText: "google.com www.google.com"
                            text: hrow.e.names ?? ""
                            onEditingFinished: if (text.trim() !== hrow.e.names) hostsTab.update(hrow.e.id, { names: text.trim() })
                        }
                        IconButton {
                            icon: "󰍉"
                            tooltip: "Test: what does this name resolve to now?"
                            onClicked: {
                                const name = (hrow.e.names ?? "").trim().split(/\s+/)[0]
                                if (!name) return
                                hrow.testResult = "…"
                                Network.lookup(name, (ok, text) => { hrow.testOk = ok; hrow.testResult = text })
                            }
                        }
                        IconButton {
                            icon: "󰆴"
                            tooltip: "Remove"
                            textColor: "#f38ba8"
                            onClicked: hostsTab.change(hostsTab.draft.filter(x => x.id !== hrow.e.id))
                        }
                        ToggleSwitch {
                            checked: hrow.e.enabled !== false
                            onToggled: v => hostsTab.update(hrow.e.id, { enabled: v })
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.bottomMargin: 8
                        visible: hrow.err !== "" && ((hrow.e.ip ?? "") !== "" || (hrow.e.names ?? "") !== "")
                        text: "󰀦  " + hrow.err
                        color: "#f38ba8"
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                    }
                    Reveal {
                        open: hrow.testResult !== ""
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.bottomMargin: 8
                            text: hrow.testResult
                            color: hrow.testOk ? Qt.rgba(1, 1, 1, 0.7) : "#f38ba8"
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }

            NetRow {
                first: hostsTab.draft.length === 0
                ActionButton {
                    icon: "󰐕"
                    text: "Add entry"
                    onClicked: hostsTab.change(hostsTab.draft.concat([{ id: "h" + Date.now(), ip: "", names: "", enabled: true }]))
                }
                Item { Layout.fillWidth: true }
                ActionButton {
                    visible: hostsTab.dirty
                    icon: "󰕌"
                    text: "Undo"
                    onClicked: hostsTab.load()
                }
                ActionButton {
                    icon: "󰌾"
                    text: "Apply"
                    primary: hostsTab.dirty || !hostsTab.inSync
                    interactive: (hostsTab.dirty || !hostsTab.inSync) && hostsTab.valid && !Network.busy
                    onClicked: {
                        Settings.set("network", "hosts", hostsTab.draft)
                        Network.applyHosts(hostsTab.draft)
                        hostsTab.dirty = false
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            text: "Apply asks for your password (it writes /etc/hosts; the previous file is kept as /etc/hosts.quickshell.bak)."
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        NetCard {
            Layout.fillWidth: true
            title: "Already in /etc/hosts  ·  read-only"
            icon: "󰈙"
            Repeater {
                model: Network.hostsOther
                NetRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    label: modelData.names
                    Chip { text: modelData.ip }
                }
            }
        }
    }

    // ── Safe apply: keep / revert (in the window's footer) ──────────────────
    Rectangle {
        parent: netPage.footerHost ?? netPage
        Layout.fillWidth: true
        Layout.preferredHeight: Network.pending !== null ? keepRow.implicitHeight + 26 : 0
        Layout.topMargin: Layout.preferredHeight > 0 ? 8 : 0
        visible: Layout.preferredHeight > 0.5
        clip: Math.abs(Layout.preferredHeight - (keepRow.implicitHeight + 26)) > 0.5   // only while sliding
        radius: 14
        color: Qt.rgba(0.98, 0.89, 0.69, 0.12)
        border.width: Properties.panelBorderWidth
        border.color: Qt.rgba(0.98, 0.89, 0.69, 0.45)
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        RowLayout {
            id: keepRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 11 }
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    text: "Keep the new settings of " + (Network.pending?.name ?? "") + "?  Reverting in " + Network.countdown + "s"
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                // drains with the countdown
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.1)
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.max(0, Network.countdown - 1) / 20
                        color: "#f9e2af"
                        Behavior on width { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
                    }
                }
            }
            ActionButton {
                icon: "󰕌"
                text: "Revert now"
                onClicked: Network.revert()
            }
            ActionButton {
                icon: "󰄬"
                text: "Keep"
                primary: true
                onClicked: Network.keep()
            }
        }
    }
}
