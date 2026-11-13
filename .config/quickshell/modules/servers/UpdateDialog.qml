import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// "What will be updated" before an update starts (ServerRuns → manage-svs.sh
// update --auto). Four kinds:
//   custom     per server: skip / security / packages / containers / everything
//              (preselected from Settings → Servers → Update defaults); one run per
//              choice, the later ones queue
//   security   just the security packages (Arch servers: the full upgrade, it has no
//              safe partial one); containers and other packages stay
//   all        everything pending: packages, containers
//   critical   everything, but only on servers with something critical
//   UpdateDialog { id: u }   u.start("security", ["svs-pbs01"])   (servers: [] = every one that has something)
Modal {
    id: root

    // (never wider than the window: at its narrowest the rows wrap instead of being cut off)
    cardWidth: Math.min(kind === "custom" ? 800 : 600, root.width - 2 * Tokens.space.s24)
    // a narrow window: controls go under their labels, the per-server choice becomes a list
    readonly property bool narrow: cardWidth < 740
    Behavior on cardWidth { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
    property string kind: "all"
    property var picked: []                 // server names (security / all / critical)
    property var choice: ({})               // custom: { name: "skip" | "security" | "os" | "containers" | "all" }
    property string reboot: ServerStore.prefs.rebootMode === "auto" ? "auto" : "none"
    property string snapshot: ServerStore.snapshotMode
    property string snapshotFail: ServerStore.snapshotFail
    // what this run would update: names (custom: the ones that aren't skipped)
    readonly property var chosen: kind === "custom" ? ServerStore.active.map(s => s.name).filter(n => (choice[n] ?? "skip") !== "skip") : picked
    readonly property bool anyGuest: chosen.some(n => !!ServerStore.get(n)?.guest)
    // custom: one run per choice, in this order
    readonly property var runOrder: ["all", "os", "containers", "security"]
    readonly property var runs: kind !== "custom" ? [] : runOrder.map(c => ({ only: c, servers: chosen.filter(n => choice[n] === c) })).filter(r => r.servers.length)

    function needs(name, k) {
        const i = ServerStore.info[name]
        if (!i || i.reachable === false) return false
        if (k === "security") return i.security > 0
        if (k === "critical") return i.critical
        return i.packages + i.containers > 0 || i.reboot
    }
    // the servers this kind can update (archived never); custom: every one
    readonly property var candidates: kind === "custom" ? ServerStore.active
                                    : ServerStore.active.filter(s => needs(s.name, kind) || picked.includes(s.name))

    function start(k, servers) {
        kind = ["custom", "security", "all", "critical"].includes(k) ? k : "all"
        showIdle = false
        snapshot = ServerStore.snapshotMode
        snapshotFail = ServerStore.snapshotFail
        if (kind === "custom") {
            const asked = servers && servers.length ? servers : null
            const c = {}
            for (const s of ServerStore.active) {
                let v = ServerStore.updateChoiceFor(s.name)
                if (asked) {
                    // selected by hand: those are updated (their default, or everything), the rest skipped
                    if (!asked.includes(s.name)) v = "skip"
                    else if (v === "skip" && ServerStore.info[s.name]?.reachable !== false) v = "all"
                }
                c[s.name] = v
            }
            choice = c
        } else {
            picked = (servers && servers.length ? servers : ServerStore.active.map(s => s.name)).filter(n => needs(n, kind))
            if (servers && servers.length && picked.length === 0) picked = servers.slice()    // asked for these: show them anyway
        }
        open()
    }
    function toggle(name) { picked = picked.includes(name) ? picked.filter(n => n !== name) : picked.concat([name]) }
    function setChoice(name, v) { const c = Object.assign({}, choice); c[name] = v; choice = c }
    function setAll(v) {
        const c = {}
        for (const s of ServerStore.active) c[s.name] = v === "defaults" ? ServerStore.updateChoiceFor(s.name)
                                                       : v === "pending" ? ServerStore.pendingChoice(s.name) : v
        choice = c
    }
    // switching between the quick kinds and custom keeps what was ticked
    function switchKind(v) {
        if (v === kind) return
        if (v === "custom") {
            const c = {}
            for (const s of ServerStore.active)
                c[s.name] = picked.includes(s.name) ? (kind === "security" ? "security" : "all") : "skip"
            choice = c
        } else {
            const from = kind === "custom" ? chosen : picked
            picked = from.filter(n => needs(n, v))
        }
        kind = v
    }
    // custom: the choices as the defaults of those servers (Settings → Servers shows them)
    function saveDefaults() {
        const m = Object.assign({}, ServerStore.prefs.updatePer ?? {})
        for (const s of ServerStore.active) {
            const v = choice[s.name] ?? "skip"
            // the same as the general default: no own entry
            if (v === ServerStore.updateDefault) delete m[s.name]; else m[s.name] = v
        }
        ServerStore.setPref("updatePer", m)
        saved.restart()
    }
    Timer { id: saved; interval: 1800 }

    // what an update of this server does, for this kind / choice
    function summary(name, what) {
        const i = ServerStore.info[name] ?? {}
        const k = what ?? kind
        const parts = []
        if (i.reachable === false) return "not reachable"
        if (!i.scanOk) parts.push(i.scanned ? "last scan failed" : "not scanned yet")
        if (k === "skip") return parts.join("  ·  ") || "not updated"
        const pk = (i.packages ?? 0) + " package" + (i.packages === 1 ? "" : "s")
        const ct = (i.containers ?? 0) + " container" + (i.containers === 1 ? "" : "s")
        if (k === "security") {
            parts.push((i.security ?? 0) + " security package" + (i.security === 1 ? "" : "s"))
            if (i.pm === "pacman") parts.push("Arch: full upgrade (" + pk + ")")
        } else if (k === "os") {
            if (i.packages) parts.push(pk + (i.security ? " (" + i.security + " security)" : ""))
            if (i.containers) parts.push("containers stay")
        } else if (k === "containers") {
            if (i.containers) parts.push(ct)
            if (i.packages) parts.push("packages stay")
        } else {
            if (i.packages) parts.push(pk + (i.security ? " (" + i.security + " security)" : ""))
            if (i.containers) parts.push(ct)
        }
        if (i.reboot && k !== "containers") parts.push("reboot needed")
        if (i.stale) parts.push("scan is out of date")
        return parts.join("  ·  ") || "nothing pending at the last scan"
    }
    function notes(name, what) {
        const s = ServerStore.get(name), i = ServerStore.info[name] ?? {}
        const k = what ?? kind
        const n = []
        if (k === "skip") return ""
        const withCt = k !== "security" && k !== "os" && (i.containers ?? 0) > 0 && i.ctMode === "update"
        const withPk = k !== "containers" && (k === "security" ? (i.security ?? 0) > 0 : (i.packages ?? 0) > 0)
        const withPlain = k !== "security" && k !== "os" && (i.plainNew ?? 0) > 0 && s?.plainContainers && i.ctMode === "update"
        // (only downloading images changes nothing that runs: no snapshot for that)
        if (s?.guest && (withCt || withPk || withPlain)) n.push(root.snapshot === "off" || s.noSnapshot ? "no snapshot" + (s.noSnapshot && root.snapshot !== "off" ? " (off for this server" + (s.noSnapshotReason ? ": " + s.noSnapshotReason : "") + ")" : "")
                                                       : "󰆓 snapshot on " + s.guest.node + " first" + (root.snapshot === "drop" ? ", deleted if it passes" : ""))
        // its snapshot needs the Proxmox host: say so now when that can't be reached
        if (s?.guest && root.snapshot !== "off" && !s.noSnapshot) {
            const h = ServerStore.info[s.guest.node]
            if (!ServerStore.get(s.guest.node)) n.push("⚠ its host " + s.guest.node + " isn't in the list: the snapshot will fail")
            else if (h && (h.reachable === false || (h.scanned && !h.scanOk))) n.push("⚠ " + s.guest.node + " can't be reached: the snapshot will fail"
                                                                                       + (root.snapshotFail === "skip" ? " and this server is skipped" : ""))
        }
        if (k !== "security" && k !== "os" && (i.containers ?? 0) > 0 && i.ctMode === "pull") n.push("containers: images only downloaded, nothing restarts")
        if (k !== "security" && k !== "os" && (i.plainNew ?? 0) > 0 && s?.plainContainers && i.ctMode === "update") n.push(i.plainNew + " plain " + (i.plainNew === 1 ? "container" : "containers") + " through Watchtower")
        // what goes down, and when (the things one wants to know before pressing the button)
        const mayReboot = root.reboot === "auto" && !i.proxmox && !s?.noReboot && k !== "containers" && (withPk || i.reboot)
        if (withCt) n.push("restarts " + i.containers + (i.containers === 1 ? " container" : " containers") + (mayReboot ? " (once, with the reboot if there is one)" : ""))
        if (mayReboot) n.push(i.reboot ? "reboots" : "reboots if the update needs it")
        else if (i.reboot && !i.proxmox && !s?.noReboot && k !== "containers") n.push("the reboot it needs stays for you")
        const ahead = root.waitsFor(name)
        if (ahead.length) n.push("waits for " + ahead.join(", ") + " (updating now, an earlier wave)")
        if (i.proxmox) n.push("Proxmox: never rebooted automatically")
        else if (s?.noReboot) n.push("never rebooted automatically")
        if ((s?.excludeContainers ?? []).length && k !== "security" && k !== "os") n.push("skips " + s.excludeContainers.join(", "))
        return n.join("  ·  ")
    }

    // servers of an earlier wave that a running update is still working on: this one waits for them
    function waitsFor(name) {
        const waves = ServerStore.data.waves ?? []
        const mine = waves.findIndex(w => w.includes(name))
        if (mine <= 0) return []
        const early = waves.slice(0, mine).reduce((a, w) => a.concat(w), [])
        return ServerRuns.busyRuns.filter(r => r.mode === "update").reduce((a, r) => a.concat(r.servers.filter(x => early.includes(x) && (r.per[x]?.status ?? "") === "" && !a.includes(x))), [])
    }
    // custom: servers with nothing waiting and nothing chosen are folded away
    property bool showIdle: false
    function idle(name) {
        const i = ServerStore.info[name] ?? {}
        return (choice[name] ?? "skip") === "skip" && i.reachable !== false && (i.packages ?? 0) + (i.containers ?? 0) === 0 && !i.reboot
    }
    readonly property int idleCount: kind === "custom" ? ServerStore.active.filter(s => idle(s.name)).length : 0

    // Something is running: can this start next to it (no server in both, D5)?
    readonly property var clash: ServerRuns.busyRuns.filter(r => r.mode === "update").reduce((a, r) => a.concat(r.servers.filter(s => root.chosen.includes(s) && !a.includes(s))), [])
    readonly property bool alongside: ServerRuns.anyBusy && root.chosen.length > 0 && ServerRuns.canAlongside("update", root.chosen)
    // how: "alongside" = next to what is running; "" = start, or wait in the queue when something runs
    function go(how) {
        const o = { reboot: root.reboot, snapshot: root.snapshot, snapshotFail: root.snapshotFail }
        if (root.kind === "custom")
            // one run per choice: next to each other when asked for, else the first starts and the others queue
            for (const r of root.runs) ServerRuns.start("update", r.servers, Object.assign({ only: r.only === "all" ? "" : r.only }, o), how)
        else ServerRuns.start("update", root.picked, Object.assign({ only: root.kind === "security" ? "security" : "" }, o), how)
        ServerStore.selecting = false
        root.close()
    }

    readonly property var title: ({ custom: "Choose what to update", security: "Install security updates", all: "Update servers",
                                    critical: "Update servers with critical updates" })
    readonly property string subtitle: kind === "custom" ? "Per server: what gets updated. Your defaults are preselected (Settings → Servers)"
                                     : kind === "security" ? "Only the security packages; containers and other packages stay for a normal update"
                                     : "Packages and containers, in your waves; checks before and after, rollback if something breaks"

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                readonly property color tone: root.kind === "security" || root.kind === "critical" ? Colors.red : Colors.accent
                implicitWidth: 38; implicitHeight: 38; radius: Tokens.radius.xl
                color: Colors.alpha(tone, 0.14)
                Text { anchors.centerIn: parent; text: root.kind === "custom" ? "󰒆" : root.kind === "all" ? "󰚰" : "󰒃"; color: parent.tone
                       font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text { text: root.title[root.kind]; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text {
                    Layout.fillWidth: true
                    text: root.subtitle
                    color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        Segmented {
            Layout.fillWidth: true
            options: [{ label: "Choose per server", value: "custom", icon: "󰒆" }, { label: "Security only", value: "security", icon: "󰒃" },
                      { label: "Servers with critical", value: "critical", icon: "󰀦" }, { label: "Everything", value: "all", icon: "󰚰" }]
            value: root.kind
            onEdited: v => root.switchKind(v)
        }

        // Proxmox snapshots of the guests: right here, before the list (this run only;
        // the default is in Settings → Servers)
        ListCard {
            Layout.fillWidth: true
            visible: root.anyGuest
            SettingRow {
                first: true
                wide: root.narrow
                label: "󰆓  Proxmox snapshots"
                desc: root.snapshot === "off" ? "none this time: a broken update can only roll its containers back"
                    : root.snapshot === "drop" ? "one before each guest's update, deleted again as soon as it passed"
                    : "one before each guest's update, kept as a rollback point (deleted after SNAPSHOT_KEEP_DAYS)"
                Segmented {
                    small: true
                    options: [{ label: "Off", value: "off" }, { label: "Keep", value: "keep" }, { label: "Delete after success", value: "drop" }]
                    value: root.snapshot
                    onEdited: v => root.snapshot = v
                }
            }
            SettingRow {
                visible: root.snapshot !== "off"
                wide: root.narrow
                label: "If a snapshot can't be taken"
                desc: root.snapshotFail === "skip" ? "that server isn't updated (safe; e.g. its Proxmox host is unreachable)" : "it's updated anyway, without a rollback point"
                Segmented {
                    small: true
                    options: [{ label: "Skip the server", value: "skip" }, { label: "Update anyway", value: "update" }]
                    value: root.snapshotFail
                    onEdited: v => root.snapshotFail = v
                }
            }
        }

        // custom: set every server at once, or back to the defaults
        // (a Flow: in a narrow window the buttons go onto a second line instead of widening the dialog)
        Flow {
            Layout.fillWidth: true
            visible: root.kind === "custom"
            spacing: Tokens.space.s6
            Text { height: 28; verticalAlignment: Text.AlignVCenter; text: "All servers:"; color: Colors.textSecondary; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
            ActionButton { implicitHeight: 28; variant: "ghost"; icon: "󰚰"; text: "What's pending"; tooltip: "Everything on servers where the last scan found something, the rest skipped"; onClicked: root.setAll("pending") }
            ActionButton { implicitHeight: 28; variant: "ghost"; icon: "󰒃"; text: "Security"; onClicked: root.setAll("security") }
            ActionButton { implicitHeight: 28; variant: "ghost"; icon: "󰜺"; text: "None"; onClicked: root.setAll("skip") }
            ActionButton { implicitHeight: 28; variant: "ghost"; icon: "󰦛"; text: "My defaults"; tooltip: "What Settings → Servers → Update defaults says"; onClicked: root.setAll("defaults") }
            ActionButton {
                implicitHeight: 28
                variant: "ghost"
                icon: saved.running ? "󰄬" : "󰆓"
                text: saved.running ? "Saved" : "Save as defaults"
                tooltip: "Next time these choices are preselected (change them in Settings → Servers)"
                onClicked: root.saveDefaults()
            }
        }

        // the servers: ticked = updated (custom: a choice per server)
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, root.kind === "custom" ? 380 : 300)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SlimScrollBar {}
            ColumnLayout {
                id: list
                width: parent.width - 14
                spacing: Tokens.space.s2
                ActionButton {
                    visible: root.kind === "custom" && root.idleCount > 0
                    variant: "ghost"; implicitHeight: Tokens.size.controlSmall
                    icon: root.showIdle ? "󰅃" : "󰅀"
                    text: root.showIdle ? "Hide the " + root.idleCount + " with nothing waiting" : root.idleCount + (root.idleCount === 1 ? " server has" : " servers have") + " nothing waiting: show"
                    onClicked: root.showIdle = !root.showIdle
                }
                Repeater {
                    model: root.kind === "custom" ? [] : root.candidates
                    Checkbox {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.name + "   —   " + root.summary(modelData.name) + (root.notes(modelData.name) ? "\n" + root.notes(modelData.name) : "")
                        checked: root.picked.includes(modelData.name)
                        onClicked: root.toggle(modelData.name)
                    }
                }
                Repeater {
                    model: root.kind === "custom" ? root.candidates : []
                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property string name: modelData.name
                        readonly property string c: root.choice[name] ?? "skip"
                        readonly property bool off: ServerStore.info[name]?.reachable === false
                        readonly property string own: ServerStore.updatePerOf(name)
                        Layout.fillWidth: true
                        visible: root.showIdle || !root.idle(name)
                        implicitHeight: rowL.implicitHeight + 2 * Tokens.space.s8
                        radius: Tokens.radius.md
                        color: c !== "skip" ? Colors.alpha(Colors.accent, 0.06) : "transparent"
                        Behavior on color { ColorAnimation { duration: Anim.fast } }
                        RowLayout {
                            id: rowL
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space.s10
                            anchors.rightMargin: Tokens.space.s6
                            spacing: Tokens.space.s10
                            Rectangle {
                                implicitWidth: 8; implicitHeight: 8; radius: 4
                                color: ServerStore.statusColor(row.name)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: row.name + (row.own ? "  ·  default " + ServerStore.choiceLabel(row.own).toLowerCase() : "")
                                    color: row.c === "skip" ? Colors.fade(0.55) : Colors.ink
                                    font.pixelSize: Tokens.font.body; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.summary(row.name, row.c)
                                    color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: root.notes(row.name, row.c)
                                    color: text.includes("⚠") ? Colors.orange : Colors.fade(0.45)
                                    font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                                }
                            }
                            Segmented {
                                visible: !root.narrow
                                small: true
                                opacity: row.off ? 0.5 : 1
                                accessibleName: "Update of " + row.name
                                options: ServerStore.updateChoices.map(o => ({ label: o.label, value: o.value }))
                                value: row.c
                                onEdited: v => root.setChoice(row.name, v)
                            }
                            Dropdown {
                                visible: root.narrow
                                Layout.preferredWidth: 150
                                opacity: row.off ? 0.5 : 1
                                options: ServerStore.updateChoices.map(o => ({ label: o.label, value: o.value }))
                                value: row.c
                                onEdited: v => root.setChoice(row.name, v)
                            }
                        }
                    }
                }
                Text {
                    visible: root.candidates.length === 0
                    text: "Nothing to update for this choice at the last scan"
                    color: Colors.textMuted; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
                }
            }
        }

        ListCard {
            Layout.fillWidth: true
            SettingRow {
                first: true
                wide: root.narrow
                label: "Reboots"
                desc: root.reboot === "auto" ? "servers that need one reboot, one after the other, and must come back" : "a needed reboot is only reported"
                Segmented {
                    small: true
                    options: [{ label: "Don't reboot", value: "none" }, { label: "Reboot when needed", value: "auto" }]
                    value: root.reboot
                    onEdited: v => { root.reboot = v; ServerStore.setPref("rebootMode", v) }
                }
            }

        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: (root.runs.length > 1 ? root.runs.length + " runs, one after the other (" + root.runs.map(r => ServerStore.choiceLabel(r.only).toLowerCase() + " " + r.servers.length).join(", ") + ")  ·  " : "")
                      + (!ServerRuns.anyBusy ? "Runs in the background; you can close the window"
                         : root.alongside ? "Something is running on other servers: this can run next to it (Enter), or after it"
                         : "Something is running" + (root.clash.length ? " on " + root.clash.slice(0, 3).join(", ") + (root.clash.length > 3 ? ", …" : "") : "")
                           + ": this waits until it is done" + (ServerRuns.queue.length ? " (place " + (ServerRuns.queue.length + 1) + " in the queue)" : ""))
                color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
            }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                visible: root.alongside
                icon: "󰔟"
                text: "Run after it"
                tooltip: "Wait in the queue until nothing is running any more"
                interactive: root.chosen.length > 0
                onClicked: root.go("")
            }
            ActionButton {
                icon: "󰚰"
                text: (root.alongside ? "Run now alongside  ·  " : ServerRuns.anyBusy ? "Queue  ·  " : "Update ") + root.chosen.length + (root.chosen.length === 1 ? " server" : " servers")
                tooltip: root.alongside ? "Start right away, next to what is running. Servers of a later wave still wait for the earlier ones." : ""
                variant: "primary"
                interactive: root.chosen.length > 0
                onClicked: root.go(root.alongside ? "alongside" : "")
            }
        }
    }
}
