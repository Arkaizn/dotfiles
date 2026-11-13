import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// The details pane of the Servers app (a card's click), a column on the right of
// the window like the file manager's info pane (the cards make room): everything about one
// server — actions, reachability (ping, Wake-on-LAN), what the last scan found
// (critical / normal packages, containers), health checks, the Proxmox host /
// guests and their update snapshots, the last update report, notes and links.
//   ServerDrawer { onEdit: s => …; onUpdate: (names, item) => …; onCommand: names => …; onMenu: (s, item, x, y) => … }
//   drawer.show(name) · drawer.hide()
Item {
    id: root

    property string name: ""
    property bool open: false
    readonly property var server: ServerStore.get(name)
    readonly property var info: ServerStore.info[name] ?? ({})
    readonly property var scan: ServerStore.scans[name] ?? null
    readonly property var check: ServerStore.checks[name] ?? null
    readonly property var guests: ServerStore.guestsOf(name)

    signal edit(var server)
    signal updateRequested(var names, Item item)
    signal command(var names)
    signal menu(var server, Item item, real x, real y)
    signal confirmDelete(string title, string text, var run)
    signal rebootRequested(var server)
    signal historyRequested(string name)
    signal pveSetupRequested(string name)
    signal logRequested(string title, string path)
    signal containerLogRequested(string name, string container)
    signal restartPulledRequested(var server, var names)   // containers whose new image is only downloaded

    // a list of "name  old → new" lines
    component PkgList: ColumnLayout {
        Layout.minimumWidth: 0
        Layout.maximumWidth: col.width
        property var items: []
        property color tone: Colors.textSecondary
        property int limit: 999
        spacing: 1
        Repeater {
            model: parent.items.slice(0, parent.limit)
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.maximumWidth: col.width
                spacing: Tokens.space.s8
                Text { Layout.preferredWidth: Math.min(200, col.width * 0.42); Layout.minimumWidth: 60; text: modelData.name; color: Colors.ink; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.from + "  →  " + modelData.to; color: parent.parent.tone; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideMiddle }
            }
        }
    }

    function show(n) {
        if (n !== name) { pingText = ""; report = null; snaps = null; picked = []; showAllPkgs = false; guestMsg = ""; flick.contentY = 0 }
        name = n
        open = true
        ServerStore.lastReport(n, r => { if (root.name === n) root.report = r })
    }
    function hide() { open = false }

    property string pingText: ""
    property bool pinging: false
    property var report: null
    property var snaps: null                // { snapshots, pools, unreachable, error }
    property var picked: []                 // snapshot ids
    property bool showAllPkgs: false
    property string guestMsg: ""                // result of Find

    // the snapshots that belong here: this guest's, or every guest's on this host
    readonly property var mySnaps: {
        if (!snaps) return []
        const s = server
        if (s?.guest) return snaps.snapshots.filter(x => x.node === s.guest.node && x.vmid === s.guest.vmid)
        return snaps.snapshots.filter(x => x.node === name)
    }

    // its width: dragged on its left edge (remembered, this device: ServerStore.prefs.paneWidth).
    // Opening / closing changes the width in one step, so the cards next to it reflow once
    // (and glide there) instead of on every frame; the pane itself slides in.
    property real maxWidth: 900
    property real dragWidth: -1
    readonly property bool resizing: dragWidth >= 0
    readonly property real paneWidth: Math.max(360, Math.min(maxWidth, resizing ? dragWidth : (Number(ServerStore.prefs.paneWidth) || 460)))
    implicitWidth: open ? paneWidth : 0
    visible: open
    clip: true

    // the divider on its left edge: drag to resize, double-click resets
    Item {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Tokens.space.s12
        z: 2
        Rectangle {
            anchors.centerIn: parent
            width: 3; height: 56; radius: 1.5
            color: Colors.fade(split.pressed ? 0.7 : split.containsMouse ? 0.45 : 0.12)
            Behavior on color { ColorAnimation { duration: Anim.fast } }
        }
        MouseArea {
            id: split
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            property real startX: 0
            property real startW: 0
            onPressed: m => { startX = mapToItem(null, m.x, 0).x; startW = root.paneWidth; root.dragWidth = startW }
            onPositionChanged: m => { if (pressed) root.dragWidth = startW - (mapToItem(null, m.x, 0).x - startX) }
            onReleased: { ServerStore.setPref("paneWidth", Math.round(root.paneWidth)); root.dragWidth = -1 }
            onDoubleClicked: { root.dragWidth = -1; ServerStore.setPref("paneWidth", 460) }
        }
    }

    Rectangle {
        id: panel
        width: root.paneWidth - Tokens.space.s12
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: Tokens.space.s12 + slide
        // slides in from the right when it opens (or shows another server)
        property real slide: 0
        onVisibleChanged: if (visible) slideIn.restart()
        Connections { target: root; function onNameChanged() { if (root.open) slideIn.restart() } }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: panel; property: "slide"; from: 40; to: 0; duration: Anim.slow; easing.type: Anim.emphasized }
            NumberAnimation { target: panel; property: "opacity"; from: 0; to: 1; duration: Anim.medium; easing.type: Anim.standard }
        }
        radius: Tokens.radius.lg
        color: Colors.card
        border.width: 1
        border.color: Colors.alpha(ServerStore.statusColor(root.name), 0.45)
        Behavior on border.color { ColorAnimation { duration: Anim.medium } }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Tokens.space.s14
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SlimScrollBar {}
            SmoothWheel { flick: flick }

            ColumnLayout {
                id: col
                width: flick.width - 14
                spacing: Tokens.space.s12

                // ── head ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s10
                    Rectangle {
                        implicitWidth: 12; implicitHeight: 12; radius: 6
                        color: ServerStore.statusColor(root.name)
                        Behavior on color { ColorAnimation { duration: Anim.medium } }
                    }
                    ServerLogo { name: root.name; size: 36 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: root.name; color: Colors.ink; font.pixelSize: Tokens.font.title; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight }
                        Text {
                            Layout.fillWidth: true
                            text: root.server ? ServerStore.destOf(root.server) + ":" + root.server.port + (root.info.osName ? "  ·  " + root.info.osName : root.info.pm ? "  ·  " + root.info.pm : "")
                                                + (root.info.proxmox ? "  ·  Proxmox" : "") + (root.server.archived ? "  ·  archived" : "") : ""
                            color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight
                        }
                    }
                    IconButton { icon: "󰇘"; tooltip: "More"; onClicked: root.menu(root.server, this, width / 2, height) }
                    IconButton { icon: "󰅖"; tooltip: "Close  (Esc)"; onClicked: root.hide() }
                }

                // ── actions ──
                // (a wrapping row in a layout: capped at the pane's width, or it stays one long line)
                Flow {
                    id: acts
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: col.width
                    spacing: Tokens.space.s6
                    ActionButton { icon: "󰆍"; text: "Terminal"; onClicked: ServerStore.ssh(root.name) }
                    ActionButton { icon: "󰉋"; text: "Files"; visible: root.server?.sftp ?? false; onClicked: ServerStore.sftp(root.name) }
                    ActionButton { icon: "󰑓"; text: "Scan"; visible: !(root.server?.archived ?? true); onClicked: ServerRuns.scanAll([root.name]) }
                    ActionButton { icon: "󰚰"; text: "Update…"; visible: !(root.server?.archived ?? true) && root.info.reachable !== false
                                   onClicked: root.updateRequested([root.name], this) }
                    ActionButton { icon: "󰆍"; text: "Run command…"; visible: !(root.server?.archived ?? true); onClicked: root.command([root.name]) }
                    ActionButton { icon: "󰏫"; text: "Edit"; onClicked: root.edit(root.server) }
                }

                // ── reachability ──
                ListCard {
                    Layout.fillWidth: true
                    SettingRow {
                        first: true
                        label: root.info.reachable === false ? "Offline" : root.info.reachable ? "Online" : "Not checked yet"
                        desc: (root.info.reachable === false && root.info.error ? root.info.error.replace(/^ssh: /, "") + "\n" : "")
                              + (root.pingText ? "ping: " + root.pingText : "ping it to see how fast it answers")
                        ActionButton {
                            icon: "󰓅"; text: "Ping"; busy: root.pinging
                            onClicked: { root.pinging = true; const n = root.name; ServerStore.ping(n, (ms, t) => { if (root.name === n) { root.pingText = t; root.pinging = false } }) }
                        }
                        ActionButton {
                            visible: (root.server?.wol ?? "") !== ""
                            icon: "󰐥"; text: "Wake"
                            tooltip: "Wake-on-LAN to " + (root.server?.wol ?? "")
                            onClicked: ServerStore.wake(root.name, (ok, t) => root.pingText = t)
                        }
                    }
                }

                // ── updates ──
                SectionTitle { text: "Updates" + (root.scan ? "  ·  scanned " + Format.ago(root.info.lastScan) + (root.info.stale ? " (out of date)" : "") : "") }
                Text {
                    visible: !root.scan
                    text: "Not scanned yet: Scan above"
                    color: Colors.textMuted; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
                }
                Banner {
                    Layout.fillWidth: true
                    visible: root.info.scanned === true && root.info.scanOk !== true
                    tone: "error"
                    title: "The last scan couldn't get in"
                    text: (root.info.scanError || "unreachable") + (/Host key verification failed/.test(root.info.scanError)
                          ? "\nThe server's SSH key isn't the one known for it (new name, reinstalled, or another machine). Check it with a Terminal session; if it's right, remove the old key: ssh-keygen -R " + ServerStore.hostOf(root.server ?? {}) : "")
                }
                Banner {
                    Layout.fillWidth: true
                    visible: root.info.reboot === true
                    tone: "warn"
                    text: "Needs a reboot" + (root.info.proxmox || root.server?.noReboot ? ": never done automatically here, reboot it by hand" : "")
                    actionText: "Reboot…"
                    onAction: root.rebootRequested(root.server)
                }
                readonly property var pkgs: (root.scan?.packages ?? [])
                Text {
                    visible: col.pkgs.some(p => p.security)
                    text: "󰒃  Critical: " + col.pkgs.filter(p => p.security).length + " security"
                    color: Colors.red; font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily
                }
                PkgList { Layout.fillWidth: true; tone: Colors.red; items: col.pkgs.filter(p => p.security).map(p => ({ name: p.name, from: p.old, to: p.new })) }
                RowLayout {
                    visible: col.pkgs.some(p => !p.security)
                    Text {
                        text: "󰚰  Packages: " + col.pkgs.filter(p => !p.security).length
                        color: Colors.textStrong; font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily
                    }
                    ActionButton { variant: "ghost"; visible: col.pkgs.filter(p => !p.security).length > 8
                                   text: root.showAllPkgs ? "Fewer" : "All"; onClicked: root.showAllPkgs = !root.showAllPkgs }
                }
                PkgList { Layout.fillWidth: true; limit: root.showAllPkgs ? 999 : 8; items: col.pkgs.filter(p => !p.security).map(p => ({ name: p.name, from: p.old, to: p.new })) }
                // containers: what an update would recreate, what only waits for a restart,
                // and the ones the tool doesn't manage (said by kind)
                readonly property string ctMode: root.info.ctMode ?? "update"
                readonly property var allCts: root.scan?.containers ?? []
                readonly property var waiting: ctMode === "update" ? [] : allCts.filter(c => c.state === "pulled")
                readonly property var newCts: allCts.filter(c => !waiting.includes(c))
                readonly property var skipped: root.scan?.skipped ?? []
                function shortId(id) { return (id ?? "").replace(/^sha256:/, "").slice(0, 12) }
                Text {
                    visible: col.newCts.length > 0
                    text: "󰡨  Containers with a new image: " + col.newCts.length
                          + (col.ctMode === "pull" ? "  ·  an update only downloads it here" : col.ctMode === "never" ? "  ·  never touched here" : "")
                    color: col.ctMode === "update" ? Colors.orange : Colors.textSecondary
                    font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily
                }
                PkgList {
                    Layout.fillWidth: true
                    tone: Colors.orange
                    items: col.newCts.map(c => ({ name: c.name, from: c.oldVersion || col.shortId(c.oldId),
                                                  to: c.newVersion || col.shortId(c.newId) || "newer image" }))
                }
                Banner {
                    Layout.fillWidth: true
                    visible: col.waiting.length > 0
                    tone: "info"
                    title: col.waiting.length + (col.waiting.length === 1 ? " container waits for a restart" : " containers wait for a restart")
                    text: col.waiting.map(c => c.name).join(", ") + "\nThe new image is downloaded; " + (col.waiting.length === 1 ? "it still runs" : "they still run")
                          + " the old one, because containers are " + (ServerStore.ctModeLabels[col.ctMode] ?? "") + " on this server."
                    actionText: "Restart…"
                    onAction: root.restartPulledRequested(root.server, col.waiting.map(c => c.name))
                }
                Text {
                    Layout.fillWidth: true
                    visible: (root.scan?.plain ?? []).length > 0
                    text: "󰡨  Plain containers with a newer image: " + (root.scan?.plain ?? []).map(p => p.name).join(", ")
                          + (root.server?.plainContainers ? (col.ctMode === "update" ? "\nUpdated with the next update, through Watchtower (run once)." : "\nNot updated: containers are " + (ServerStore.ctModeLabels[col.ctMode] ?? "") + " on this server.")
                                                          : "\nNot updated: plain containers are off for this server (Edit → Update plain containers).")
                    color: root.server?.plainContainers && col.ctMode === "update" ? Colors.orange : Colors.textSecondary
                    font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    readonly property var plain: col.skipped.filter(k => k.kind === "plain").map(k => k.name)
                    readonly property int aio: col.skipped.filter(k => k.kind === "aio").length
                    text: (root.scan?.warnings ?? []).map(w => "⚠ " + w)
                          .concat(plain.length ? ["· Plain (started with docker run, not from Compose): " + plain.join(", ")] : [])
                          .concat(aio ? ["· " + aio + " managed by Nextcloud AIO: it updates them itself, the tool leaves them alone"] : [])
                          .concat(col.skipped.filter(k => k.kind !== "plain" && k.kind !== "aio").map(k => "· " + k.name + ": " + k.reason)).join("\n")
                    color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                }

                // ── health ──
                SectionTitle {
                    visible: (root.check?.checks ?? []).length + (root.check?.containers ?? []).length > 0
                    text: "Health  ·  checked " + (root.check ? Format.ago(root.info.lastCheck) : "never")
                }
                Repeater {
                    model: root.check?.checks ?? []
                    Pressable {
                        id: ck
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        interactive: modelData.type === "http"
                        dimDisabled: false
                        tooltip: modelData.type === "http" ? "Open " + modelData.target : modelData.target
                        onClicked: ServerStore.openUrl(modelData.target)
                        RowLayout {
                            anchors.fill: parent
                            spacing: Tokens.space.s8
                            Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: ck.modelData.ok ? Colors.green : Colors.red }
                            Text { Layout.preferredWidth: 140; text: ck.modelData.name; color: ck.hovered ? Colors.accent : Colors.ink; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: ck.modelData.ok ? ck.modelData.type + "  " + ck.modelData.target : ck.modelData.detail
                                   color: ck.modelData.ok ? Colors.textMuted : Colors.red; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideMiddle }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: (root.check?.containers ?? []).length > 0
                    readonly property var bad: (root.check?.containers ?? []).filter(c => c.status !== "running" || c.health === "unhealthy")
                    text: "󰡨  " + (root.check?.containers ?? []).length + " containers" + (bad.length ? ", not fine: " + bad.map(c => c.name + " (" + (c.health === "unhealthy" ? "unhealthy" : c.status) + ")").join(", ") : ", all running")
                    color: bad.length ? Colors.orange : Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                }

                // ── Proxmox: where it runs (editable here), its guests if it's a host ──
                SectionTitle { text: "Proxmox" }
                ListCard {
                    id: pmx
                    Layout.fillWidth: true
                    Layout.maximumWidth: col.width
                    readonly property var g: root.server?.guest ?? null
                    readonly property var hosts: ServerStore.proxmoxHosts.filter(h => h !== root.name)
                                                     .concat(g && !ServerStore.proxmoxHosts.includes(g.node) ? [g.node] : [])
                    SettingRow {
                        first: true
                        visible: ServerStore.isHost(root.server) || root.server?.kind === "pbs"
                        label: ServerStore.kindLabel(root.server)
                        desc: root.server?.kind === "pbs" ? "updated like the others; never rebooted by the tool"
                            : root.guests.length + (root.guests.length === 1 ? " of your servers runs" : " of your servers run") + " on it; snapshots before their updates are taken here. Never rebooted by the tool"
                        ActionButton { visible: root.server?.kind !== "pbs"; icon: "󰒓"; text: "Access and guests…"
                                       tooltip: "Check that the tool can work with it, and link its VMs and containers to your servers"
                                       onClicked: root.pveSetupRequested(root.name) }
                    }
                    SettingRow {
                        first: !(ServerStore.isHost(root.server) || root.server?.kind === "pbs")
                        visible: !ServerStore.isHost(root.server) && root.server?.kind !== "pbs"
                        label: "Runs on"
                        desc: root.guestMsg !== "" ? root.guestMsg
                            : pmx.g ? (pmx.g.type === "lxc" ? "LXC container " : "VM ") + pmx.g.vmid + " on " + pmx.g.node
                            : root.guests.length ? "a Proxmox host (" + root.guests.length + (root.guests.length === 1 ? " guest" : " guests") + " below)"
                            : "not a Proxmox guest (a separate machine)"
                        Dropdown {
                            options: [{ label: "Not on Proxmox", value: "" }].concat(pmx.hosts.map(h => ({ label: h, value: h })))
                            value: pmx.g?.node ?? ""
                            onEdited: v => { root.guestMsg = ""; ServerStore.setGuest(root.name, v === "" ? null
                                                : { node: v, type: pmx.g?.type ?? "qemu", vmid: pmx.g?.vmid ?? 100 }) }
                        }
                        ActionButton {
                            icon: "󰍉"; text: "Find"
                            tooltip: "Ask the Proxmox hosts where a VM / container named " + root.name + " runs"
                            busy: ServerStore.finding
                            onClicked: {
                                const n = root.name
                                root.guestMsg = "asking " + ServerStore.proxmoxHosts.join(", ") + "…"
                                ServerStore.findGuest(n, r => {
                                    if (root.name !== n) return
                                    if (r.guest) { ServerStore.setGuest(n, r.guest); root.guestMsg = "found: " + (r.guest.type === "lxc" ? "LXC " : "VM ") + r.guest.vmid + " on " + r.guest.node }
                                    else root.guestMsg = r.error
                                })
                            }
                        }
                    }
                    SettingRow {
                        visible: !!pmx.g
                        label: "Type and ID"
                        desc: "as in Proxmox (qm / pct)"
                        Segmented {
                            small: true
                            options: [{ label: "VM", value: "qemu" }, { label: "LXC", value: "lxc" }]
                            value: pmx.g?.type ?? "qemu"
                            onEdited: v => ServerStore.setGuest(root.name, Object.assign({}, pmx.g, { type: v }))
                        }
                        SearchField {
                            Layout.preferredWidth: 90
                            icon: ""; clearable: false
                            text: String(pmx.g?.vmid ?? "")
                            validator: IntValidator { bottom: 100; top: 999999999 }
                            onEditingFinished: { const v = parseInt(text); if (v >= 100 && v !== pmx.g?.vmid) ServerStore.setGuest(root.name, Object.assign({}, pmx.g, { vmid: v })) }
                        }
                    }
                    SettingRow {
                        visible: !!pmx.g
                        label: "Snapshot before updates"
                        desc: root.server?.noSnapshot ? "never for this server (e.g. an LXC with a bind mount: Proxmox can't snapshot those)"
                                                      : "as set in the update confirmation / Settings → Servers"
                        ToggleSwitch { checked: !(root.server?.noSnapshot ?? false); onToggled: v => ServerStore.setNoSnapshot(root.name, !v) }
                    }
                }
                Repeater {
                    model: root.guests
                    Pressable {
                        id: gr
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        tooltip: "Open " + modelData.name
                        onClicked: root.show(modelData.name)
                        RowLayout {
                            anchors.fill: parent
                            spacing: Tokens.space.s8
                            Text { text: "  └"; color: Colors.textFaint; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                            Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 3.5
                                        color: ServerStore.statusColor(gr.modelData.name) }
                            Text { Layout.fillWidth: true; text: gr.modelData.name + "   " + (gr.modelData.guest.type === "lxc" ? "LXC " : "VM ") + gr.modelData.guest.vmid
                                   color: gr.hovered ? Colors.accent : Colors.textSecondary; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                        }
                    }
                }
                // update snapshots (svsupd_*): loaded on demand (asks every Proxmox node)
                RowLayout {
                    visible: !!root.server?.guest || root.guests.length > 0
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: !root.snaps ? "Update snapshots: not loaded"
                            : root.snaps.error ? "Snapshots: " + root.snaps.error
                            : root.mySnaps.length + " update snapshot" + (root.mySnaps.length === 1 ? "" : "s")
                              + ((root.snaps.unreachable ?? []).length ? "  ·  unreachable: " + root.snaps.unreachable.join(", ") : "")
                        color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                    }
                    ActionButton { icon: "󰑓"; text: root.snaps ? "Reload" : "Load"; busy: ServerStore.snapshotsLoading
                                   onClicked: { const n = root.name; ServerStore.loadSnapshots(r => { if (root.name === n) { root.snaps = r; root.picked = [] } }) } }
                }
                Repeater {
                    model: root.mySnaps
                    Checkbox {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.name + " (" + modelData.vmid + ")  ·  " + modelData.snapshot + "  ·  " + modelData.ageDays + " d old"
                        checked: root.picked.includes(modelData.id)
                        onClicked: root.picked = checked ? root.picked.filter(x => x !== modelData.id) : root.picked.concat([modelData.id])
                    }
                }
                ActionButton {
                    visible: root.picked.length > 0
                    icon: "󰆴"; variant: "danger"
                    text: "Delete " + root.picked.length + " snapshot" + (root.picked.length === 1 ? "" : "s") + "…"
                    onClicked: {
                        const ids = root.picked.slice()
                        root.confirmDelete("Delete " + ids.length + " snapshot" + (ids.length === 1 ? "" : "s") + "?",
                                           "Rolling back to them is no longer possible afterwards. Only the update snapshots (svsupd_*) can be deleted here.",
                                           () => { ServerRuns.start("snapshots", [], { ids: ids }); root.picked = []; root.snaps = null })
                    }
                }

                // ── last update ──
                SectionTitle { visible: root.report !== null; text: "Last update" }
                ColumnLayout {
                    visible: root.report !== null
                    Layout.fillWidth: true
                    spacing: 2
                    readonly property var r: root.report?.server ?? ({})
                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: col.width
                        wrapMode: Text.Wrap
                        text: (root.report ? new Date(root.report.time).toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm") : "") + "  ·  " + (parent.r.status ?? "")
                              + "  ·  " + (parent.r.packages ?? []).length + " packages, " + (parent.r.containers ?? []).length + " containers"
                              + (parent.r.snapshot && parent.r.snapshot !== "-" ? "  ·  snapshot " + parent.r.snapshot : "")
                        color: ["failed", "unreachable"].includes(parent.r.status) ? Colors.red : parent.r.status === "rolled-back" ? Colors.orange : Colors.textSecondary
                        font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                    }
                    ResultRow {
                        Layout.fillWidth: true
                        Layout.maximumWidth: col.width
                        name: root.name
                        result: parent.r
                        logPath: root.report ? ServerStore.serverLogOf(root.report.log, root.name) : ""
                        onLogRequested: (t, f) => root.logRequested(t, f)
                        onCheckRequested: n => ServerRuns.start("check", [n], {}, "alongside")
                        onContainerLogRequested: (n, c) => root.containerLogRequested(n, c)
                        onDetailsRequested: n => {}
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (parent.r.notes ?? []).length > 0 && (parent.r.summary ?? "") === ""
                        text: (parent.r.notes ?? []).map(n => "· " + n).join("\n")
                        color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                    }
                    ActionButton { variant: "ghost"; icon: "󰋚"; text: "All its updates…"; onClicked: root.historyRequested(root.name) }
                }

                // ── links / notes ──
                SectionTitle { visible: (root.server?.links ?? []).length > 0; text: "Links" }
                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: col.width
                    visible: (root.server?.links ?? []).length > 0
                    spacing: Tokens.space.s6
                    Repeater {
                        model: root.server?.links ?? []
                        ActionButton { required property var modelData; icon: "󰖟"; text: modelData.name; tooltip: modelData.url; onClicked: ServerStore.openUrl(modelData.url) }
                    }
                }
                SectionTitle { visible: (root.server?.notes ?? "") !== ""; text: "Notes" }
                Text {
                    Layout.fillWidth: true
                    visible: (root.server?.notes ?? "") !== ""
                    text: root.server?.notes ?? ""
                    color: Colors.textSecondary; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                Item { implicitHeight: Tokens.space.s8 }
            }
        }
    }
}
