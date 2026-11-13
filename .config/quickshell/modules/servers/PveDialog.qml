import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import Quickshell
import qs.components

// Setting up a Proxmox VE host: can the tool work with it (the checks, each with what to
// do when it fails), and its guests — link them to your servers by picking, or add them.
// Nobody types a VM ID.
//   PveDialog { id: p }   p.start("svs-pve02")
Modal {
    id: root

    cardWidth: 860
    property string host: ""
    property var checks: null               // null = not asked yet
    property var guests: null
    property string guestError: ""
    property var pick: ({})                 // "type:vmid" → server name | "+" (add) | "" (leave)
    property var failed: []
    readonly property bool ready: checks !== null && checks.every(c => c.ok)

    // how it is reached: over SSH (qm / pct, as root) or through its API with a token
    property string mode: "ssh"
    property string fUrl: ""
    property string fToken: ""
    property string fSecret: ""             // only what is typed now; the stored one is never read back
    property string fNode: ""
    property bool fApiOnly: false
    property bool hasToken: false
    property var nodes: []
    property var cert: null                 // { pin, fingerprint } of a certificate that isn't trusted yet
    property string problem: ""
    property bool working: false
    property bool editing: false            // the API fields are shown although it already works
    readonly property bool fields: mode === "api" && (!ready || editing)
    readonly property var srv: ServerStore.get(host)
    readonly property string savedPin: srv?.pve?.pin ?? ""

    function key(g) { return g.type + ":" + g.vmid }
    function start(name) {
        host = name; checks = null; guests = null; guestError = ""; pick = ({}); failed = []; cert = null; problem = ""; fSecret = ""; nodes = []
        const p = ServerStore.get(name)?.pve
        mode = p?.access === "api" ? "api" : "ssh"
        fUrl = p?.url || "https://" + ServerStore.hostOf(ServerStore.get(name)) + ":8006"
        fToken = p?.tokenId ?? ""
        fNode = p?.node ?? ""
        fApiOnly = p?.apiOnly ?? false
        hasToken = false
        editing = false
        open()
        if (mode === "ssh") { run(); return }
        // set up before: check it. Started but not finished (no trusted certificate yet): go on
        // there. (Only once it is known whether a secret is stored: save() asks for one otherwise.)
        ServerStore.hasPveToken(name, yes => {
            if (root.host !== name) return
            root.hasToken = yes
            if (fToken !== "" && savedPin !== "") run()
            else if (fToken !== "" && yes) save("")
        })
    }
    function pveNow(pin) { return { access: mode, url: fUrl.trim().replace(/\/+$/, ""), tokenId: fToken.trim(), node: fNode, pin: pin, apiOnly: mode === "api" && fApiOnly } }

    // Save how it is reached, then ask the script whether that works.
    // API: the certificate is looked at first. A new one (first time, or it changed) is
    // shown with its fingerprint and has to be accepted before the token is ever sent.
    function save(trust) {
        problem = ""
        if (mode === "ssh") { ServerStore.setPve(host, pveNow(savedPin)); run(); return }
        const url = fUrl.trim().replace(/\/+$/, "")
        if (!/^https:\/\/[A-Za-z0-9.-]+(:[0-9]+)?$/.test(url)) { problem = "The address looks like https://host:8006"; return }
        if (!/^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+![A-Za-z0-9._-]+$/.test(fToken.trim())) { problem = "The token ID looks like user@realm!name, e.g. quickshell@pve!snap"; return }
        if (fSecret.trim() === "" && !hasToken) { problem = "Paste the token's secret (Proxmox shows it once, when the token is made)"; return }
        const h = host
        working = true
        ServerStore.pvePin(url, r => {
            if (root.host !== h) return
            if (r.error) { working = false; problem = r.error; return }
            if (r.pin !== savedPin && trust !== r.pin) { working = false; cert = r; return }      // ask first
            cert = null
            const go = () => { ServerStore.setPve(h, pveNow(r.pin)); working = false; run() }
            if (fSecret.trim() !== "") ServerStore.storePveToken(h, fSecret.trim(), ok => {
                if (!ok) { working = false; problem = "Couldn't put the secret into the keyring (is it unlocked?)"; return }
                fSecret = ""; hasToken = true; go()
            })
            else go()
        })
    }
    function run() {
        const h = host
        checks = null; guests = null; guestError = ""
        ServerStore.pveInfo(h, info => {
            if (root.host !== h) return
            nodes = info.nodes ?? []
            // one node and none chosen (or a wrong one): that's the one
            if (info.access === "api" && nodes.length === 1 && fNode !== nodes[0]) { fNode = nodes[0]; ServerStore.setPve(h, pveNow(savedPin)); run(); return }
            checks = info.checks
            if (!info.checks.every(c => c.ok)) return
            const mine = (info.guests ?? []).slice().sort((a, b) => a.vmid - b.vmid)
            const p = {}
            for (const g of mine) {
                // linked already → that server; else a server with the guest's name; else leave
                const linked = ServerStore.servers.find(s => s.guest && s.guest.node === h && s.guest.vmid === g.vmid)
                // (a Backup Server is never suggested: a snapshot of it would take its datastore along)
                const same = ServerStore.servers.find(s => !s.guest && s.name !== h && !ServerStore.isHost(s) && !ServerStore.isPbs(s) && [s.name, ServerStore.hostOf(s), ServerStore.hostOf(s).split(".")[0]].map(x => x.toLowerCase()).includes(g.name.toLowerCase()))
                p[root.key(g)] = linked ? linked.name : same ? same.name : ""
            }
            pick = p
            guests = mine
        })
    }
    function linkedTo(g) { return ServerStore.servers.find(s => s.guest && s.guest.node === root.host && s.guest.vmid === g.vmid)?.name ?? "" }
    readonly property var changes: (guests ?? []).filter(g => (pick[key(g)] ?? "") !== "" && pick[key(g)] !== linkedTo(g))
    function options(g) {
        // servers that aren't a guest somewhere else, and not the host itself
        const free = ServerStore.servers.filter(s => !s.archived && s.name !== root.host && !ServerStore.isHost(s)
                                                     && (!s.guest || (s.guest.node === root.host && s.guest.vmid === g.vmid)))
        return [{ label: "Not one of my servers", value: "" }].concat(free.map(s => ({ label: s.name, value: s.name })))
               .concat(ServerStore.get(g.name) ? [] : [{ label: "Add " + g.name + " as a new server", value: "+" }])
    }
    function apply() {
        failed = ServerStore.takeGuests(host, changes.map(g => ({ guest: g, server: pick[key(g)] })))
        if (failed.length === 0) close()
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s10
            ServerLogo { name: root.host; size: Tokens.icon.app }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: root.host + "  ·  Proxmox VE host"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: "Snapshots before updates are taken here. Its guests are your servers that run on it."
                       color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
            }
            ActionButton { icon: "󰑓"; text: "Check again"; busy: ServerStore.checking || root.working; onClicked: root.save("") }
            IconButton { icon: "󰅖"; tooltip: "Close  (Esc)"; onClicked: root.close() }
        }

        SectionTitle { text: "Access" }
        ListCard {
            Layout.fillWidth: true
            SettingRow {
                first: true
                label: "How the tool reaches it"
                desc: root.mode === "api" ? "through its API, with a token that may only look at guests and snapshot them. Nothing else on the host can be done with it"
                                          : "over SSH, running qm / pct as root: no setup, but it is a root login on the hypervisor"
                wide: true
                Segmented {
                    small: true
                    options: [{ label: "SSH", value: "ssh" }, { label: "API token", value: "api" }]
                    value: root.mode
                    onEdited: v => { root.mode = v; root.checks = null; root.guests = null; root.cert = null; root.problem = ""; root.editing = false; if (v === "ssh") root.save("") }
                }
                ActionButton { visible: root.mode === "api" && root.ready && !root.editing; variant: "ghost"; icon: "󰏫"; text: "Change…"; onClicked: root.editing = true }
            }
            SettingRow {
                visible: root.fields
                label: "Address"
                desc: "the web interface's, without a path"
                SearchField { Layout.preferredWidth: 320; icon: "󰖟"; clearable: false; placeholderText: "https://pve02:8006"; text: root.fUrl; onTextChanged: root.fUrl = text; onAccepted: root.save("") }
            }
            SettingRow {
                visible: root.fields
                label: "Token ID"
                desc: "user@realm!name"
                SearchField { Layout.preferredWidth: 320; icon: "󰌆"; clearable: false; placeholderText: "quickshell@pve!snap"; text: root.fToken; onTextChanged: root.fToken = text; onAccepted: root.save("") }
            }
            SettingRow {
                visible: root.fields
                label: "Secret"
                desc: root.hasToken ? "one is in your keyring; paste a new one only to replace it" : "kept in your keyring, nowhere else"
                SearchField { Layout.preferredWidth: 320; icon: "󰌾"; clearable: false; password: true; placeholderText: root.hasToken ? "••••••••  (stored)" : "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                              text: root.fSecret; onTextChanged: root.fSecret = text; onAccepted: root.save("") }
            }
            SettingRow {
                visible: root.fields && root.nodes.length > 1
                label: "Its node"
                desc: "the API of a cluster answers for every node: which one is " + root.host + "?"
                Dropdown { Layout.preferredWidth: 200; options: root.nodes.map(n => ({ label: n, value: n })); value: root.fNode; onEdited: v => { root.fNode = v; root.save("") } }
            }
            SettingRow {
                visible: root.fields
                label: "No SSH to it at all"
                desc: "the tool then never logs in on the host: it doesn't scan or update the host itself, only snapshots its guests. Leave off to keep updating the host over SSH"
                ToggleSwitch { checked: root.fApiOnly; onToggled: v => root.fApiOnly = v }
            }
            SettingRow {
                visible: root.fields
                label: "Making the token"
                desc: "on the host, as root (Copy puts these four commands on the clipboard). The last one prints the secret, once"
                wide: true
                ActionButton {
                    icon: "󰆏"; text: "Copy"
                    onClicked: Quickshell.execDetached(["wl-copy", "--", "pveum role add QuickshellSnap -privs \"VM.Audit,VM.Snapshot,VM.Snapshot.Rollback\"\npveum user add quickshell@pve\npveum aclmod /vms -user quickshell@pve -role QuickshellSnap\npveum user token add quickshell@pve snap --privsep 0\n"])
                }
                ActionButton { variant: root.ready ? "default" : "primary"; icon: "󰄬"; text: "Save and check"; busy: root.working || ServerStore.checking; onClicked: root.save("") }
            }
        }
        Banner {
            Layout.fillWidth: true
            visible: root.problem !== ""
            tone: "error"
            text: root.problem
        }
        Banner {
            Layout.fillWidth: true
            visible: root.cert !== null
            tone: "warn"
            title: root.savedPin === "" ? "Is this its certificate?" : "Its certificate changed"
            text: "SHA-256 fingerprint: " + (root.cert?.fingerprint ?? "") + "\nCompare it with the one in the Proxmox web interface (the node → System → Certificates). The token is only ever sent to a host that shows this certificate"
                  + (root.savedPin === "" ? "." : ". If you didn't renew it, don't accept: someone may be answering in its place.")
            actionText: "It matches: trust it"
            onAction: root.save(root.cert.pin)
        }
        Rectangle {
            Layout.fillWidth: true
            visible: root.checks !== null || ServerStore.checking
            implicitHeight: acc.implicitHeight + Tokens.space.s20
            radius: Tokens.radius.card
            color: Colors.card
            border.width: Tokens.border.thin
            border.color: Properties.cardBorder
            ColumnLayout {
                id: acc
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.space.s14
                spacing: Tokens.space.s10
                RowLayout {
                    visible: root.checks === null
                    spacing: Tokens.space.s8
                    Spinner { running: parent.visible; size: Tokens.font.small }
                    Text { text: "Asking " + root.host + "…"; color: Colors.textMuted; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
                }
                Repeater {
                    model: root.checks ?? []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.space.s10
                        Text { text: modelData.ok ? "󰄬" : "󰅖"; color: modelData.ok ? Colors.green : Colors.red; font.pixelSize: Tokens.font.label; font.family: Properties.fontFamily; Layout.alignment: Qt.AlignTop }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: modelData.text; color: Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
                            Text { Layout.fillWidth: true; visible: modelData.hint !== ""; text: modelData.hint; color: Colors.orange; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
                        }
                    }
                }
            }
        }

        SectionTitle { visible: root.ready; text: "Its guests" + (root.guests ? "  ·  " + root.guests.length : "") }
        Item {
            visible: root.ready
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.fields ? 180 : 320, Math.max(64, (root.guests ?? []).length * 46))
            Spinner { anchors.centerIn: parent; visible: root.guests === null; running: visible }
            EmptyState { anchors.centerIn: parent; visible: root.guests !== null && root.guests.length === 0; icon: "󰒋"; text: root.guestError !== "" ? root.guestError : "No VMs or containers on it" }
            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.guests ?? []
                spacing: Tokens.space.s4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SlimScrollBar {}
                SmoothWheel { flick: list; step: 92 }
                delegate: RowLayout {
                    id: row
                    required property var modelData
                    readonly property string cur: root.pick[root.key(modelData)] ?? ""
                    readonly property bool changed: cur !== "" && cur !== root.linkedTo(modelData)
                    width: list.width - 14
                    height: 42
                    spacing: Tokens.space.s10
                    Rectangle {
                        implicitWidth: 46; implicitHeight: 22; radius: Tokens.radius.sm
                        color: Colors.fillSubtle; border.width: Tokens.border.thin; border.color: Colors.lineControl
                        Text { anchors.centerIn: parent; text: row.modelData.type === "lxc" ? "LXC" : "VM"; color: Colors.textSecondary; font.pixelSize: Tokens.font.micro; font.bold: true; font.family: Properties.fontFamily }
                    }
                    Text { Layout.preferredWidth: 48; text: String(row.modelData.vmid); color: Colors.textMuted; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
                    Text { Layout.fillWidth: true; text: row.modelData.name; color: Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight }
                    Text { visible: row.changed; text: row.cur === "+" ? "new" : "link"; color: Colors.accent; font.pixelSize: Tokens.font.caption; font.bold: true; font.family: Properties.fontFamily }
                    Dropdown {
                        Layout.preferredWidth: 300
                        options: root.options(row.modelData)
                        value: row.cur
                        onEdited: v => { const p = Object.assign({}, root.pick); p[root.key(row.modelData)] = v; root.pick = p }
                    }
                }
            }
        }

        Banner {
            Layout.fillWidth: true
            visible: root.failed.length > 0
            tone: "error"
            title: "Couldn't add"
            text: root.failed.join("\n")
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: !root.ready ? "Fix what's marked above, then Check again" : root.changes.length === 0 ? "Every guest is where you want it"
                    : root.changes.length + (root.changes.length === 1 ? " change" : " changes") + ": a linked server gets a snapshot here before each update"
                color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
            }
            ActionButton { text: root.changes.length ? "Cancel" : "Close"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                visible: root.ready
                icon: "󰄬"
                text: "Apply" + (root.changes.length ? " " + root.changes.length : "")
                variant: "primary"
                interactive: root.changes.length > 0
                onClicked: root.apply()
            }
        }
    }
}
