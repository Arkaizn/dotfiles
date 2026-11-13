import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Add / edit a server (servers.json through ServerStore).
//   ServerEditor { id: ed }   ed.start(null) = new, ed.start(server) = edit
// Health checks and web links are edited as lines, like svs.conf:
//   http  name  http://host:port/path  [expected codes, e.g. 200|401]
//   tcp   name  host:port            dns name server [domain]
//   service name unit.service        cmd name <shell command on the server>
//   links: name  https://url
Modal {
    id: root

    cardWidth: 620
    property string oldName: ""             // "" = a new server
    property var base: null                 // the server being edited (keeps fields this form doesn't show)
    property string error: ""

    // form state
    property string fName: ""
    property string fHost: ""
    property int fPort: 22
    property string fUser: ""
    property var fGroups: []
    property string fTags: ""
    property bool fSftp: true
    property bool fNoReboot: false
    property bool fNoSnapshot: false
    property string fKind: ""               // "" a server | pve | pbs
    property string fWhy: ""                // why it can't be snapshotted
    signal pveSetupRequested(string name)
    property int fWave: -1                  // the wave it is updated in (-1 = with the rest, last)
    property string fCt: ""                 // "" automatic | update | pull | never
    property bool fPlain: false
    property string fIcon: ""               // "" = automatic, a logo name, or the path of an image
    property string fNode: ""
    property string fType: "qemu"
    property int fVmid: 100
    property string fChecks: ""
    property string fLinks: ""
    property string fExclude: ""
    property string fWol: ""
    property string fNotes: ""

    function start(s) {
        base = s
        oldName = s ? s.name : ""
        fName = s?.name ?? ""
        fHost = s?.host ?? ""
        fPort = s?.port ?? 22
        fUser = s?.user ?? ""
        fGroups = (s?.groups ?? []).slice()
        fTags = (s?.tags ?? []).join(", ")
        fSftp = s ? s.sftp : true
        fNoReboot = s?.noReboot ?? false
        fNoSnapshot = s?.noSnapshot ?? false
        fCt = s?.containers ?? ""
        fWave = s ? ServerStore.waveOf(s.name) : -1
        fKind = s?.kind ?? ""
        fWhy = s?.noSnapshotReason ?? ""
        fPlain = s?.plainContainers ?? false
        fIcon = s?.icon ?? ""
        fNode = s?.guest?.node ?? ""
        fType = s?.guest?.type ?? "qemu"
        fVmid = s?.guest?.vmid ?? 100
        fChecks = (s?.checks ?? []).map(c => c.type === "cmd" ? ["cmd", c.name, c.target].join("  ")
                                                              : [c.type, c.name, c.target, c.expect].filter(x => x).join("  ")).join("\n")
        fLinks = (s?.links ?? []).map(l => l.name + "  " + l.url).join("\n")
        fExclude = (s?.excludeContainers ?? []).join(", ")
        fWol = s?.wol ?? ""
        fNotes = s?.notes ?? ""
        error = ""
        flick.contentY = 0
        open()
        nameField.forceActiveFocus()
    }

    readonly property var checkTypes: ["http", "tcp", "dns", "service", "cmd"]
    // lines → checks; returns { list, error }
    function parseChecks(text) {
        const list = []
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i].trim()
            if (l === "" || l.startsWith("#")) continue
            const m = /^(\S+)\s+(\S+)\s+(.+)$/.exec(l)
            if (!m || !checkTypes.includes(m[1])) return { list: [], error: "check line " + (i + 1) + ": type name target (type: " + checkTypes.join(", ") + ")" }
            if (m[1] === "cmd") { list.push({ type: "cmd", name: m[2], target: m[3].trim(), expect: "" }); continue }
            const rest = m[3].trim().split(/\s+/)
            list.push({ type: m[1], name: m[2], target: rest[0], expect: rest[1] ?? "" })
        }
        return { list: list, error: "" }
    }
    function parseLinks(text) {
        const list = []
        for (const raw of text.split("\n")) {
            const l = raw.trim()
            if (l === "") continue
            const m = /^(.*?)\s*(https?:\/\/\S+)$/.exec(l)
            if (m) list.push({ name: m[1] || m[2], url: m[2] })
        }
        return list
    }
    function csv(t) { return t.split(",").map(x => x.trim()).filter(x => x !== "") }

    function save() {
        const name = fName.trim()
        const ck = parseChecks(fChecks)
        if (ck.error) { error = ck.error; return }
        if (fHost.trim() !== "" && !/^[A-Za-z0-9._:\[\]-]+$/.test(fHost.trim())) { error = "Host: a name or address, no spaces"; return }
        if (fUser.trim() !== "" && !/^[A-Za-z0-9._-]+$/.test(fUser.trim())) { error = "User: letters, digits, . _ -"; return }
        if (fWol.trim() !== "" && !/^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(fWol.trim())) { error = "Wake-on-LAN: a MAC address like aa:bb:cc:dd:ee:ff"; return }
        if (fNode !== "" && fVmid < 100) { error = "Proxmox guest: the ID is 100 or higher"; return }
        const s = Object.assign({}, base ?? {}, {
            name: name, host: fHost.trim(), port: fPort, user: fUser.trim(), groups: fGroups,
            tags: csv(fTags), sftp: fSftp, noReboot: fNoReboot, noSnapshot: fNoSnapshot, containers: fCt, plainContainers: fPlain, kind: fKind, noSnapshotReason: fNoSnapshot ? fWhy.trim() : "", icon: fIcon,
            guest: fNode !== "" ? { node: fNode, type: fType, vmid: fVmid } : null,
            checks: ck.list, links: parseLinks(fLinks), excludeContainers: csv(fExclude),
            wol: fWol.trim(), notes: fNotes, archived: base?.archived ?? false
        })
        const e = ServerStore.put(s, oldName)
        if (e) { error = "Name: " + e; return }
        if (ServerStore.waveOf(name) !== fWave) ServerStore.setWave(name, fWave)
        // a new Proxmox host (or one that just became one): on to its access check and its guests
        const becameHost = fKind === "pve" && (base?.kind ?? "") !== "pve"
        close()
        if (becameHost) pveSetupRequested(name)
    }

    // ── small form pieces ──
    component Label: Text {
        color: Colors.textSecondary
        font.pixelSize: Tokens.font.caption
        font.bold: true
        font.family: Properties.fontFamily
    }
    component Field: SearchField {
        Layout.fillWidth: true
        icon: ""
        clearable: false
    }
    component Lines: ScrollView {
        id: lines
        property alias text: area.text
        property string placeholder: ""
        property bool mono: false
        Layout.fillWidth: true
        Layout.preferredHeight: 96
        TextArea {
            id: area
            placeholderText: lines.placeholder
            wrapMode: TextEdit.NoWrap
            color: Properties.color
            placeholderTextColor: Colors.fade(0.35)
            selectionColor: Colors.fade(0.28)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            leftPadding: Tokens.space.s14
            rightPadding: Tokens.space.s14
            topPadding: Tokens.space.s10
            background: FieldBackground { focused: area.activeFocus }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: "󰒋"; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text { text: root.oldName ? "Edit " + root.oldName : "New server"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text { text: "Saved in servers.json next to manage-svs.sh (this device only)"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(form.implicitHeight, Math.max(240, (root.parent?.height ?? 800) - 260))
            contentHeight: form.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SlimScrollBar {}
            SmoothWheel { flick: flick }

            ColumnLayout {
                id: form
                width: flick.width - 14
                spacing: Tokens.space.s10

                // connection
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Tokens.space.s10
                    rowSpacing: Tokens.space.s6
                    Label { text: "Name (also the SSH host if Host is empty)" }
                    Label { text: "Host" }
                    Field { id: nameField; placeholderText: "svs-docker01"; text: root.fName; onTextChanged: root.fName = text; onAccepted: root.save() }
                    Field { placeholderText: "same as the name"; text: root.fHost; onTextChanged: root.fHost = text; onAccepted: root.save() }
                    Label { text: "User" }
                    Label { text: "SSH port" }
                    Field { placeholderText: "from ~/.ssh/config"; text: root.fUser; onTextChanged: root.fUser = text; onAccepted: root.save() }
                    Field { placeholderText: "22"; text: String(root.fPort); validator: IntValidator { bottom: 1; top: 65535 }
                            onTextChanged: root.fPort = parseInt(text) || 22; onAccepted: root.save() }
                }

                // groups
                Label { text: "Groups" }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s6
                    Repeater {
                        model: ServerStore.groups
                        FilterChip {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.name
                            checked: root.fGroups.includes(modelData.id)
                            onToggled: root.fGroups = checked ? root.fGroups.filter(g => g !== modelData.id) : root.fGroups.concat([modelData.id])
                        }
                    }
                    Text {
                        visible: ServerStore.groups.length === 0
                        text: "No groups yet (+ New group at the top of the window)"
                        color: Colors.textFaint
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                    }
                }
                Label { text: "Tags (comma separated, for the search)" }
                Field { placeholderText: "e.g. media, critical"; text: root.fTags; onTextChanged: root.fTags = text }

                // its picture: automatic (what the scan sees), one of the logos, or any image file
                Label { text: "Picture" + (root.fIcon === "" ? "  ·  automatic: Proxmox, Docker or the distro, from the scan"
                                        : root.fIcon.startsWith("/") ? "  ·  " + root.fIcon : "  ·  " + root.fIcon) }
                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: form.width
                    spacing: Tokens.space.s4
                    FilterChip { text: "Automatic"; icon: "󰁨"; checked: root.fIcon === ""; onToggled: root.fIcon = "" }
                    Repeater {
                        model: ServerStore.logos
                        Pressable {
                            id: lb
                            required property string modelData
                            implicitWidth: 32; implicitHeight: 32
                            tooltip: modelData
                            onClicked: root.fIcon = modelData
                            Rectangle {
                                anchors.fill: parent
                                radius: Tokens.radius.md
                                color: root.fIcon === lb.modelData ? Colors.fade(0.16) : lb.hovered ? Colors.fade(0.08) : "transparent"
                                border.width: root.fIcon === lb.modelData ? 1 : 0
                                border.color: Colors.accent
                                Behavior on color { ColorAnimation { duration: Anim.fast } }
                            }
                            Image {
                                anchors.centerIn: parent
                                width: 20; height: 20
                                source: ServerStore.logoUrl(lb.modelData)
                                sourceSize: Qt.size(40, 40)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }
                    }
                    ActionButton {
                        icon: "󰋩"; text: "Image file…"
                        onClicked: Jobs.pickFile({ title: "A picture for this server", start: ServerStore.home + "/", filters: ["Images | *.svg *.png *.jpg *.jpeg *.webp"] },
                                                 p => { if (p) root.fIcon = p })
                    }
                }

                // options
                ListCard {
                    Layout.fillWidth: true
                    SettingRow {
                        first: true
                        label: "What is it"
                        desc: root.fKind === "pve" ? "a Proxmox VE host: your other servers can run on it, snapshots are taken here, and it is never rebooted by the tool. Saving goes on to its access check and its guests"
                            : root.fKind === "pbs" ? "a Proxmox Backup Server: updated like the others, never rebooted by the tool, no guests"
                            : "a normal server (a VM, a container or a machine of its own)"
                        wide: true
                        Segmented {
                            small: true
                            options: [{ label: "Server", value: "" }, { label: "Proxmox VE host", value: "pve" }, { label: "Proxmox Backup Server", value: "pbs" }]
                            value: root.fKind
                            onEdited: v => { root.fKind = v; if (v !== "") root.fNoReboot = true }
                        }
                    }
                    SettingRow {
                        label: "Files (SFTP)"
                        desc: "the Files button opens it in your default file manager"
                        ToggleSwitch { checked: root.fSftp; onToggled: v => root.fSftp = v }
                    }
                    SettingRow {
                        label: "Never reboot automatically"
                        desc: "updates report a needed reboot instead (Proxmox hosts never reboot automatically anyway)"
                        ToggleSwitch { checked: root.fNoReboot; onToggled: v => root.fNoReboot = v }
                    }
                    SettingRow {
                        label: "Update order"
                        desc: "servers of one wave update together; the next wave starts when they are done. Put what others need (DNS, the proxy) in a later wave of its own"
                        Dropdown {
                            Layout.preferredWidth: 220
                            options: ServerStore.waves.map((w, i) => ({ label: "Wave " + (i + 1), value: i, hint: w.filter(n => n !== root.oldName).slice(0, 3).join(", ") + (w.length > 4 ? ", …" : "") }))
                                     .concat([{ label: "A new wave, after those", value: ServerStore.waves.length }, { label: "With the rest (last)", value: -1 }])
                            value: root.fWave
                            onEdited: v => root.fWave = v
                        }
                    }
                    SettingRow {
                        label: "Containers on an update"
                        desc: root.fCt === "update" || (root.fCt === "" && !root.fNoReboot) ? "recreated on their new images"
                            : root.fCt === "never" ? "never touched; the scan still shows what is new"
                            : "only the new images are downloaded: they keep running until you restart them from the details" + (root.fCt === "" ? " (automatic: this server never reboots)" : "")
                        wide: true
                        Segmented {
                            small: true
                            options: [{ label: "Automatic", value: "" }, { label: "Update", value: "update" }, { label: "Download only", value: "pull" }, { label: "Never", value: "never" }]
                            value: root.fCt
                            onEdited: v => root.fCt = v
                        }
                    }
                    SettingRow {
                        label: "Update plain containers"
                        desc: "the ones started with docker run, not from Compose: through Watchtower, run once on the server for each update (a helper with access to Docker there). No automatic rollback for these"
                        ToggleSwitch { checked: root.fPlain; onToggled: v => root.fPlain = v }
                    }
                    SettingRow {
                        visible: root.fNode !== ""
                        label: "Never take a Proxmox snapshot"
                        desc: "for guests Proxmox can't snapshot (an LXC with a bind mount, passed-through disks): updated without one instead of skipped"
                        ToggleSwitch { checked: root.fNoSnapshot; onToggled: v => root.fNoSnapshot = v }
                    }
                    SettingRow {
                        visible: root.fNode !== "" && root.fNoSnapshot
                        label: "Why not"
                        desc: "shown wherever the missing snapshot matters, so nobody wonders later"
                        wide: true
                        SearchField { Layout.preferredWidth: 340; icon: ""; clearable: false; placeholderText: "e.g. LXC with a bind mount; a 3 TB disk would be part of it"
                                      text: root.fWhy; onTextChanged: root.fWhy = text }
                    }
                }

                // Proxmox guest: snapshots before updating
                Label { text: "Proxmox guest (a snapshot is taken before each update)" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s8
                    Dropdown {
                        Layout.preferredWidth: 200
                        // the known Proxmox hosts; none known yet (nothing scanned): every server
                        options: [{ label: "— not a guest —", value: "" }].concat(
                                    (ServerStore.proxmoxHosts.length ? ServerStore.proxmoxHosts.concat(root.fNode && !ServerStore.proxmoxHosts.includes(root.fNode) ? [root.fNode] : [])
                                                                     : ServerStore.servers.map(s => s.name))
                                    .filter(n => n !== root.oldName).map(n => ({ label: "on " + n, value: n })))
                        value: root.fNode
                        onEdited: v => root.fNode = v
                    }
                    Segmented {
                        visible: root.fNode !== ""
                        small: true
                        options: [{ label: "VM", value: "qemu" }, { label: "LXC", value: "lxc" }]
                        value: root.fType
                        onEdited: v => root.fType = v
                    }
                    Text { visible: root.fNode !== ""; text: "ID"; color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                    SearchField { visible: root.fNode !== ""; Layout.preferredWidth: 110; icon: ""; clearable: false; placeholderText: "105"
                                  text: String(root.fVmid); validator: IntValidator { bottom: 100; top: 999999999 }
                                  onTextChanged: root.fVmid = parseInt(text) || 0 }
                    Item { Layout.fillWidth: true }
                }

                Label { text: "Health checks (one per line: type  name  target  [expected])" }
                Lines {
                    mono: true
                    Layout.preferredHeight: 120
                    text: root.fChecks
                    onTextChanged: root.fChecks = text
                    placeholder: "http  immich  http://svs-docker01:2283/api/server/ping\ntcp   ssh     svs-docker01:22\nservice docker docker.service"
                }
                Label { text: "Web links (name  url; http checks show as links too)" }
                Lines {
                    text: root.fLinks
                    onTextChanged: root.fLinks = text
                    Layout.preferredHeight: 70
                    placeholder: "Proxmox  https://pve02:8006"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Tokens.space.s10
                    rowSpacing: Tokens.space.s6
                    Label { text: "Never update these containers (comma separated)" }
                    Label { text: "Wake-on-LAN (MAC)" }
                    Field { placeholderText: "e.g. pihole"; text: root.fExclude; onTextChanged: root.fExclude = text }
                    Field { placeholderText: "aa:bb:cc:dd:ee:ff"; text: root.fWol; onTextChanged: root.fWol = text }
                }

                Label { text: "Notes" }
                Lines {
                    text: root.fNotes
                    onTextChanged: root.fNotes = text
                    placeholder: "Anything worth knowing about this server"
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            color: Colors.red
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                icon: "󰆓"
                text: root.oldName ? "Save" : "Add server"
                variant: "primary"
                interactive: root.fName.trim() !== ""
                onClicked: root.save()
            }
        }
    }
}
