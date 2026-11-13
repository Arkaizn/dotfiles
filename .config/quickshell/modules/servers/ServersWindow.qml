import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// Servers app: your homelab servers (services/ServerStore.qml, the engine is
// scripts/servers/manage-svs.sh). Groups as foldable sections of cards (or a
// compact list), search + quick filters, terminal / files / web links per
// server, add / edit / archive, groups.
//
// Open it with:  qs ipc call servers open   (or the "Servers" launcher entry)
// Scans / updates: ServerRuns (detached manage-svs.sh --json); the bottom panel shows them.
// Keys: Ctrl+F or / search · Ctrl+N new server · Ctrl+G new group · F5 check who's online
//       Ctrl+R scan all · Ctrl+L the activity panel · Esc clear the search
Scope {
    id: root

    property alias open: persist.open
    PersistentProperties {
        id: persist
        reloadableId: "serversWindow"
        property bool open: false
    }

    readonly property string windowTitle: "Quickshell Servers"
    function show() {
        if (root.open) Compositor.focusWindow(root.windowTitle)
        root.open = true
    }
    property var pending: null               // { edit: name } | { add: true } | { update: { kind, servers } }

    readonly property var api: ({
        open: () => root.show(),
        toggle: () => { root.open = !root.open },
        close: () => root.open = false,
        edit: name => { root.pending = { edit: name }; root.show() },
        add: () => { root.pending = { add: true }; root.show() },
        // the update confirmation (a notification's "Update critical"): never starts by itself
        confirmUpdate: (kind, servers) => { root.pending = { update: { kind: kind, servers: servers ?? [] } }; root.show() },
        transfer: mode => { root.pending = { transfer: mode }; root.show() },
        details: name => { root.pending = { details: name }; root.show() },
        history: name => { root.pending = { history: name ?? "" }; root.show() },
        log: name => { root.pending = { log: name }; root.show() },
        pve: name => { root.pending = { pve: name }; root.show() }
    })
    Component.onCompleted: Panels.register("servers", api)
    Component.onDestruction: Panels.unregister("servers", api)

    IpcHandler {
        target: "servers"
        function open(): void { root.show() }
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
        function add(): void { root.api.add() }
        function edit(name: string): void { root.api.edit(name) }
        // servers: comma separated ("" = every one that has something); only opens the confirmation
        function details(name: string): void { root.api.details(name) }
        // the past updates ("" = all, or one server's), and the log of a server's last update
        function history(name: string): void { root.api.history(name) }
        function log(name: string): void { root.api.log(name) }
        // a Proxmox host's access check and its guests
        function pve(name: string): void { root.api.pve(name) }
        // put a server before another one of the same group ("" = at the end; group id, or
        // __ungrouped): what dragging a card inside its group does
        function place(group: string, name: string, before: string): string {
            const g = group === "__ungrouped" ? ServerStore.active.filter(s => !s.groups.some(x => ServerStore.groupMap[x])) : ServerStore.active.filter(s => s.groups.includes(group))
            if (!g.some(s => s.name === name) || (before !== "" && !g.some(s => s.name === before))) return "no such server in that group"
            ServerStore.placeIn(group, name, before, ServerStore.ordered(g, group).map(s => s.name))
            return ServerStore.ordered(g, group).map(s => s.name).join(" ")
        }
        function transfer(mode: string): void { root.api.transfer(mode) }
        function confirmUpdate(kind: string, servers: string): void { root.api.confirmUpdate(kind, servers.split(",").filter(x => x !== "")) }
        function list(): string {
            return ServerStore.servers.map(s => s.name + (s.archived ? " (archived)" : "") + "\t" + ServerStore.destOf(s) + ":" + s.port
                                               + "\t" + s.groups.join(",")).join("\n")
        }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: root.windowTitle
            implicitWidth: 1240
            implicitHeight: 820
            minimumSize: Qt.size(720, 480)
            color: "transparent"
            visible: true
            onVisibleChanged: if (!visible) root.open = false

            property string query: ""
            property string filter: "all"          // all | updates | critical | offline | reboot | failing
            // the activity panel: opens by itself when something starts
            property bool showRun: ServerRuns.anyBusy
            Connections {
                target: ServerRuns
                function onAnyBusyChanged() { if (ServerRuns.anyBusy) win.showRun = true }
                // another run started next to one that is going: it is the one shown now
                function onCurIdChanged() { if (ServerRuns.busy) win.showRun = true }
                // the script asks something: open the panel on it
                function onAsksChanged() { if (ServerRuns.asks.length) win.showRun = true }
            }
            // a reboot by hand: says what goes down with it
            function askReboot(s) {
                const guests = ServerStore.guestsOf(s.name).map(g => g.name)
                const i = ServerStore.info[s.name] ?? {}
                confirm.ask("Reboot " + s.name + "?",
                    (guests.length ? "It's a Proxmox host: its " + guests.length + " guests go down with it (" + guests.join(", ") + ") and come back if they start at boot.\n" : "")
                    + (i.docker ? "Its containers stop and come back with Docker.\n" : "")
                    + (i.reboot ? "The last scan says it needs one." : "The last scan doesn't say it needs one."),
                    "Reboot", () => ServerStore.reboot(s.name))
            }
            // Abort in the panel: an update asks first (and offers the hard kill once it's aborting)
            function abortRun() {
                const r = ServerRuns.run
                if (!r || !ServerRuns.busy) return
                if (r.aborting) confirm.ask("Kill the update now?",
                    "It's already stopping at the next safe point. Killing it cuts it off right now: a package install or a container that is being recreated can be left half done, and you'd have to repair that server by hand.",
                    "Kill now", () => ServerRuns.killRun())
                else if (r.mode === "update") confirm.ask("Abort the update?",
                    "Every server stops at its next safe point: waiting and verifying end right away, a package install or container update that is running finishes first. Servers that haven't started aren't touched. Nothing is rolled back.",
                    "Abort", () => ServerRuns.abortRun())
                else ServerRuns.abortRun()
            }
            // ── dragging a card onto a group ──
            property string dragName: ""
            property string dragFrom: ""
            property point dragAt: Qt.point(0, 0)      // pointer, in bg coordinates
            property point dragGrab: Qt.point(0, 0)
            property string dragOver: ""               // group id under the pointer
            // inside its own group: the card it would land before ("" = at the end), and the
            // names shown there (the order the drop is worked out in)
            property string dragBefore: ""
            property var dragShown: []
            readonly property bool reordering: dragName !== "" && dragOver !== "" && dragOver === dragFrom && dragOver !== "__archived"
            function dragStart(s, from, scenePos, grab) {
                dragName = s.name; dragFrom = from
                dragGrab = Qt.point(Math.min(grab.x, 200), Math.min(grab.y, 40))
                dragMove(scenePos)
                ghost.start()
            }
            function dragMove(scenePos) {
                dragAt = bg.mapFromItem(null, scenePos.x, scenePos.y)
                const q = bg.mapToItem(sections, dragAt.x, dragAt.y)
                const it = sections.childAt(q.x, q.y)
                dragOver = it && it.gid !== undefined && it.visible ? it.gid : ""
                if (dragOver !== "" && dragOver === dragFrom && it.dropTarget) { dragBefore = it.dropTarget(scenePos); dragShown = it.shownNames() }
            }
            function dragEnd() {
                const to = dragOver, name = dragName, from = dragFrom
                const move = name !== "" && to !== "" && to !== from
                // dropped among the cards of its own group: that's its place from now on
                const place = reordering && dragBefore !== name
                ghost.finish(move || place)
                if (move) ServerStore.dropOn(name, from, to)
                else if (place) ServerStore.placeIn(to, name, dragBefore, dragShown)
                dragName = ""; dragOver = ""
            }
            // near the top / bottom edge while dragging: scroll
            Timer {
                interval: 16; repeat: true
                running: win.dragName !== ""
                onTriggered: {
                    const y = bg.mapToItem(flick, win.dragAt.x, win.dragAt.y).y
                    const d = y < 50 ? -(50 - y) / 3 : y > flick.height - 50 ? (y - flick.height + 50) / 3 : 0
                    if (d !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + d))
                }
            }

            // a card's click: its details pane; the same card again closes it
            // (in Select mode it ticks the card instead)
            function details(name) {
                if (ServerStore.selecting && !ServerStore.get(name)?.archived) { ServerStore.toggleSelected(name); return }
                if (drawer.open && drawer.name === name) drawer.hide(); else drawer.show(name)
            }
            // ── Select mode ──
            readonly property var shownActive: ServerStore.active.filter(s => win.shown(s))
            function startSelecting(name) {
                ServerStore.selecting = true
                if (name) ServerStore.selectOnly(ServerStore.selection.filter(n => n !== name).concat([name]))
            }
            Component.onDestruction: ServerStore.selecting = false
            // the header's Update: the quick menu, or straight to Choose (Settings → Servers)
            function updateButton(item) {
                if (ServerStore.selecting && ServerStore.selection.length) updateDialog.start("custom", ServerStore.selection)
                else updateDialog.start("all", [])
            }

            function updateMenu(item, x, y, servers) {
                const scope = servers && servers.length ? ServerStore.active.filter(s => servers.includes(s.name)) : ServerStore.active
                const one = scope.length === 1
                // what each choice would update: packages (and containers), and on how many servers
                const sum = (f, key) => scope.filter(s => updateDialog.needs(s.name, f)).reduce((n, s) => n + (ServerStore.info[s.name]?.[key] ?? 0), 0)
                const nsrv = f => scope.filter(s => updateDialog.needs(s.name, f)).length
                const what = (f, pk, ct) => {
                    const n = nsrv(f)
                    if (n === 0) return "nothing"
                    const parts = [pk + (pk === 1 ? " package" : " packages")].concat(ct ? [ct + (ct === 1 ? " container" : " containers")] : [])
                    return parts.join(", ") + (one ? "" : " on " + n + (n === 1 ? " server" : " servers"))
                }
                const e = [
                    { icon: "󰒆", label: one ? "Choose what to update…" : "Choose per server what to update…", run: () => updateDialog.start("custom", servers) },
                    { sep: true },
                    { icon: "󰒃", label: "Security updates only  ·  " + what("security", sum("security", "security"), 0), run: () => updateDialog.start("security", servers) }
                ]
                if (!one) e.push({ icon: "󰀦", label: "Servers with critical updates  ·  " + what("critical", sum("critical", "packages"), sum("critical", "containers")),
                                   run: () => updateDialog.start("critical", servers) })
                e.push({ icon: "󰚰", label: "Everything  ·  " + what("all", sum("all", "packages"), sum("all", "containers")), run: () => updateDialog.start("all", servers) })
                menu.show(item, x, y, one ? scope[0].name : "Update", e)
            }

            Component.onCompleted: {
                ServerStore.probe()
                Qt.callLater(takePending)
                keys.forceActiveFocus()
            }
            Connections {
                target: root
                function onPendingChanged() { Qt.callLater(win.takePending) }
            }
            function takePending() {
                const p = root.pending
                if (!p) return
                root.pending = null
                if (p.update) updateDialog.start(p.update.kind, p.update.servers)
                else if (p.transfer) transfer.start(p.transfer)
                else if (p.details) drawer.show(p.details)
                else if (p.history !== undefined) historyDialog.start(p.history)
                else if (p.pve) { if (ServerStore.get(p.pve)) pveDialog.start(p.pve) }
                else if (p.log) ServerStore.lastReport(p.log, r => { if (r) logDialog.start(p.log, ServerStore.serverLogOf(r.log, p.log)) })
                else if (p.add) editor.start(null)
                else if (p.edit) { const s = ServerStore.get(p.edit); if (s) editor.start(s) }
            }
            // who's online: again every minute while the window is open
            Timer { interval: 60000; repeat: true; running: true; onTriggered: ServerStore.probe() }

            // ── search + quick filters ──
            function hay(s) {
                return [s.name, s.host, s.user, s.notes, ServerStore.info[s.name]?.pm ?? ""]
                       .concat(s.tags).concat(s.groups.map(g => ServerStore.groupMap[g]?.name ?? g)).join(" ").toLowerCase()
            }
            function passes(s, f) {
                const i = ServerStore.info[s.name] ?? {}
                switch (f) {
                case "updates": return (i.packages ?? 0) + (i.containers ?? 0) > 0
                case "critical": return i.critical === true
                case "offline": return i.reachable === false
                case "reboot": return i.reboot === true
                case "failing": return (i.checksFailed ?? 0) > 0 || (i.containersBad ?? 0) > 0
                case "restart": return (i.restartPending ?? 0) > 0
                case "fine": return i.scanOk === true && i.reachable !== false && !i.critical && (i.packages ?? 0) + (i.containers ?? 0) + (i.restartPending ?? 0) + (i.checksFailed ?? 0) + (i.containersBad ?? 0) === 0
                }
                return true
            }
            function shown(s) {
                if (!passes(s, filter)) return false
                const words = query.toLowerCase().split(/\s+/).filter(w => w !== "")
                if (words.length === 0) return true
                const h = hay(s)
                return words.every(w => h.includes(w))
            }
            function count(f) { return ServerStore.active.filter(s => passes(s, f)).length }
            // what needs attention, worst first, in words: the chips under the header (each one
            // filters) and the header's line
            readonly property var needs: [
                { id: "offline", icon: "󰅛", one: "offline", many: "offline", tone: Colors.textSecondary },
                { id: "failing", icon: "󰀦", one: "failing check", many: "with failing checks", tone: Colors.red },
                { id: "critical", icon: "󰒃", one: "needs attention", many: "need attention", tone: Colors.red, tip: "Security updates, or a reboot that is needed" },
                { id: "updates", icon: "󰚰", one: "has updates", many: "have updates", tone: Colors.orange },
                { id: "restart", icon: "󰜉", one: "waits for a restart", many: "wait for a restart", tone: Colors.orange, tip: "New images are downloaded, the containers still run the old ones" }
            ].map(x => Object.assign({ n: win.count(x.id) }, x)).filter(x => x.n > 0)
            readonly property int nUpdates: count("updates")
            readonly property string statusLine: {
                const n = ServerStore.active.length
                if (n === 0) return ""
                const when = ServerStore.lastScan ? "last scan " + Format.hm(ServerStore.lastScan) + " (" + Format.ago(ServerStore.lastScan) + ")" : ""
                if (!ServerStore.lastScan) return n + (n === 1 ? " server" : " servers") + ", not scanned yet"
                if (needs.length === 0) return (n === 1 ? "It is" : "All " + n + " are") + " up to date and healthy  ·  " + when
                return needs.slice(0, 3).map(x => x.n + " " + (x.n === 1 ? x.one : x.many)).join("  ·  ") + (needs.length > 3 ? "  ·  …" : "") + "  ·  " + when
            }
            // one primary action: update when something is waiting, else scan
            readonly property bool wantsUpdate: (ServerStore.selecting && ServerStore.selection.length > 0) || nUpdates > 0
            // a narrow window: the header keeps what is needed most, the rest is in its menu
            readonly property bool compact: width / zoomArea.zoom < 1060
            readonly property bool searching: query.trim() !== "" || filter !== "all"
            readonly property int matches: ServerStore.servers.filter(s => shown(s)).length

            // ── menus ──
            // What one does with a server from its card. Kept short: its details open with a
            // click, its groups are in Edit (and by dragging the card), selecting is the header's
            // Select, "choose what to update" is in the update confirmation.
            function cardMenu(s, item, x, y) {
                const e = [{ icon: "󰆍", label: "Terminal (SSH)", run: () => ServerStore.ssh(s.name) }]
                if (s.sftp) e.push({ icon: "󰉋", label: "Files (SFTP)", run: () => ServerStore.sftp(s.name) })
                for (const l of ServerStore.webLinks(s).slice(0, 3))
                    e.push({ icon: "󰖟", label: "Open " + l.name, run: () => ServerStore.openUrl(l.url) })
                e.push({ sep: true })
                if (!s.archived) {
                    e.push({ icon: "󰑓", label: "Scan + health checks", run: () => ServerRuns.scanAll([s.name]) })
                    e.push({ icon: "󰓙", label: "Health checks only", run: () => ServerRuns.start("check", [s.name], {}, "alongside") })
                    e.push({ icon: "󰚰", label: "Update…", run: () => updateDialog.start("all", [s.name]) })
                    e.push({ icon: "󰆍", label: "Run command…", run: () => commandDialog.start([s.name]) })
                    e.push({ icon: "󰜉", label: "Reboot…", run: () => win.askReboot(s) })
                    if (s.wol) e.push({ icon: "󰐥", label: "Wake-on-LAN", run: () => ServerStore.wake(s.name, (ok, t) => ServerStore.notify(s.name, t)) })
                    if (ServerStore.isHost(s)) e.push({ icon: "󰒓", label: "Access and guests…", run: () => pveDialog.start(s.name) })
                    e.push({ sep: true })
                }
                e.push({ icon: "󰏫", label: "Edit…", run: () => editor.start(s) })
                e.push({ icon: "󰋚", label: "Its updates…", run: () => historyDialog.start(s.name) })
                e.push({ icon: "󰌆", label: "Copy SSH key to it", run: () => ServerStore.copyKey(s.name) })
                e.push({ sep: true })
                e.push(s.archived ? { icon: "󰀦", label: "Restore (track it again)", run: () => ServerStore.archiveAnimated(s.name, false) }
                                  : { icon: "󰀼", label: "Archive (stop tracking)", run: () => ServerStore.archiveAnimated(s.name, true) })
                e.push({ icon: "󰆴", label: "Delete…", danger: true, run: () => confirm.ask("Delete " + s.name + "?",
                    "It's removed from servers.json, so manage-svs.sh stops updating it too. Archive it instead to keep its settings.",
                    "Delete", () => { drawer.hide(); ServerStore.removeAnimated(s.name) }) })
                menu.show(item, x, y, s.name, e)
            }
            function groupMenu(g, item, x, y) {
                const i = ServerStore.groups.findIndex(x => x.id === g.id)
                menu.show(item, x, y, g.name, [
                    { icon: "󰏫", label: "Rename / icon…", run: () => groupDialog.start(g) },
                    { icon: "󰁝", label: "Move up", run: () => ServerStore.moveGroup(g.id, -1), disabled: i === 0 },
                    { icon: "󰁅", label: "Move down", run: () => ServerStore.moveGroup(g.id, 1), disabled: i === ServerStore.groups.length - 1 },
                    { sep: true },
                    { icon: "󰆴", label: "Delete group…", danger: true, run: () => confirm.ask("Delete the group " + g.name + "?",
                        "Its servers stay; they just aren't in this group anymore.", "Delete group", () => ServerStore.deleteGroup(g.id)) }
                ].filter(x => !x.disabled))
            }

            ZoomArea {
                id: zoomArea
                app: "servers"
                anchors.fill: parent
                Rectangle {
                    id: bg
                    anchors.fill: parent
                    radius: Compositor.appRadius / zoomArea.zoom
                    color: Colors.alpha(Colors.background, 0.9)

                    Item {
                        id: keys
                        focus: true
                        Keys.onPressed: event => {
                            if (editor.shown || groupDialog.shown || confirm.shown || updateDialog.shown || commandDialog.shown || transfer.shown || historyDialog.shown || logDialog.shown || pveDialog.shown) return
                            if (event.key === Qt.Key_Escape && drawer.open) { drawer.hide(); event.accepted = true; return }
                            if (event.key === Qt.Key_Escape && ServerStore.selecting) { ServerStore.selecting = false; event.accepted = true; return }
                            const ctrl = event.modifiers & Qt.ControlModifier
                            if (ctrl && event.key === Qt.Key_A) { ServerStore.selecting = true; ServerStore.selectOnly(win.shownActive.map(s => s.name)); event.accepted = true; return }
                            if (ctrl && event.key === Qt.Key_F || event.key === Qt.Key_Slash) search.forceActiveFocus()
                            else if (ctrl && event.key === Qt.Key_N) editor.start(null)
                            else if (ctrl && event.key === Qt.Key_G) groupDialog.start(null)
                            else if (event.key === Qt.Key_F5) ServerStore.probe()
                            else if (ctrl && event.key === Qt.Key_R) ServerRuns.scanAll()
                            else if (ctrl && event.key === Qt.Key_L) win.showRun = !win.showRun
                            else if (event.key === Qt.Key_Escape && win.searching) { search.text = ""; win.filter = "all" }
                            else return
                            event.accepted = true
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.space.s16
                        spacing: Tokens.space.s12

                        AppHeader {
                            Layout.fillWidth: true
                            title: "Servers"
                            // what needs attention, in words (never wrapped: it shortens when the window is narrow)
                            subtitle: win.statusLine
                            wrapSubtitle: false
                            Segmented {
                                small: true
                                accessibleName: "View"
                                options: [{ label: "", icon: "󰕰", value: "cards" }, { label: "", icon: "󰕲", value: "list" }]
                                value: ServerStore.view
                                onEdited: v => ServerStore.setPref("view", v)
                            }
                            IconButton {
                                icon: "󰑓"
                                tooltip: "Check who's online  (F5)"
                                busy: ServerStore.probing
                                onClicked: ServerStore.probe()
                            }
                            IconButton {
                                icon: "󰦪"
                                tooltip: ServerRuns.busyRuns.length > 1 ? ServerRuns.busyRuns.length + " runs going: show them  (Ctrl+L)" : ServerRuns.anyBusy ? "Running: show what it does  (Ctrl+L)" : "Last run  (Ctrl+L)"
                                interactive: ServerRuns.run !== null
                                active: win.showRun && !ServerRuns.dismissed
                                busy: ServerRuns.anyBusy && !win.showRun
                                // (a finished run that went away by itself comes back with this)
                                onClicked: { if (ServerRuns.dismissed) { ServerRuns.dismissed = false; win.showRun = true } else win.showRun = !win.showRun }
                            }
                            ActionButton {
                                icon: "󰑓"
                                text: ServerRuns.running("scan") ? "Scanning…" : ServerRuns.running("check") ? "Checking…" : "Scan"
                                variant: !win.wantsUpdate && !ServerRuns.anyBusy && ServerStore.active.length > 0 ? "primary" : "default"
                                busy: ServerRuns.running("scan") || ServerRuns.running("check")
                                tooltip: "Scan every server for updates, then run the health checks  (Ctrl+R)"
                                onClicked: ServerRuns.scanAll()
                            }
                            IconButton {
                                icon: "󰄲"
                                tooltip: ServerStore.selecting ? "Done selecting  (Esc)" : "Select servers: then update, scan or run a command on just those  (Ctrl+A: all shown)"
                                active: ServerStore.selecting
                                onClicked: ServerStore.selecting = !ServerStore.selecting
                            }
                            ActionButton {
                                icon: "󰚰"
                                // says what it will take: "Update 3 servers…"; nothing waiting: it rests
                                text: ServerStore.selecting && ServerStore.selection.length ? "Update " + ServerStore.selection.length + " selected…"
                                    : win.nUpdates > 0 ? "Update " + win.nUpdates + (win.nUpdates === 1 ? " server…" : " servers…")
                                    : ServerRuns.running("update") ? "Updating…" : "Update"
                                variant: win.wantsUpdate ? "primary" : "default"
                                interactive: win.wantsUpdate
                                tooltip: win.wantsUpdate ? "Choose what gets updated and see what it does, before anything starts" : "Nothing to update at the last scan"
                                onClicked: win.updateButton(this)
                            }
                            ActionButton { visible: !win.compact; icon: "󰉋"; text: "New group"; onClicked: groupDialog.start(null) }
                            IconButton {
                                icon: "󰇘"
                                tooltip: "Run command, import, export, settings"
                                onClicked: menu.show(this, width / 2, height, "Servers", [
                                    { icon: "󰆍", label: "Run a command…", run: () => commandDialog.start([]) },
                                    { icon: "󰉋", label: "New group…", run: () => groupDialog.start(null), hide: !win.compact },
                                    { sep: true },
                                    { icon: "󰋚", label: "Past updates…", run: () => historyDialog.start("") },
                                    { sep: true },
                                    { icon: "󰋺", label: "Import…", run: () => transfer.start("import") },
                                    { icon: "󰈝", label: "Export…", run: () => transfer.start("export") },
                                    { sep: true },
                                    { icon: "󰒓", label: "Settings", run: () => Panels.call("settings", "openPage", "servers") }
                                ].filter(x => !x.hide))
                            }
                            ActionButton { visible: !win.compact; icon: "󰐕"; text: "Add server"; tooltip: "Ctrl+N"; onClicked: editor.start(null) }
                            IconButton { visible: win.compact; icon: "󰐕"; tooltip: "Add server  (Ctrl+N)"; onClicked: editor.start(null) }
                        }

                        // search + quick filters
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space.s10
                            SearchField {
                                id: search
                                Layout.preferredWidth: win.compact ? 220 : 340
                                placeholderText: win.compact ? "Search  (Ctrl+F)" : "Search servers, groups, tags, notes  (Ctrl+F)"
                                onTextChanged: win.query = text
                                Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space.s6
                                FilterChip {
                                    icon: "󰒋"
                                    text: "All " + ServerStore.active.length
                                    checked: win.filter === "all"
                                    onToggled: win.filter = "all"
                                }
                                Repeater {
                                    model: win.needs
                                    FilterChip {
                                        required property var modelData
                                        icon: modelData.icon
                                        text: modelData.n + " " + (modelData.n === 1 ? modelData.one : modelData.many)
                                        tooltip: modelData.tip ?? ""
                                        checked: win.filter === modelData.id
                                        onToggled: win.filter = win.filter === modelData.id ? "all" : modelData.id
                                    }
                                }
                                // the filter that is on although nothing matches any more (it emptied while you looked)
                                FilterChip {
                                    visible: win.filter !== "all" && !win.needs.some(x => x.id === win.filter)
                                    icon: "󰅖"; text: "Nothing left here"; checked: true
                                    onToggled: win.filter = "all"
                                }
                            }
                            Segmented {
                                small: true
                                accessibleName: "Order of the servers"
                                options: [{ label: "Worst first", value: "worst" }, { label: "My order", value: "mine" }]
                                value: ServerStore.sortMode
                                onEdited: v => ServerStore.setPref("sort", v)
                            }
                        }

                        // (the order of the cards: what needs attention first, or the one I dragged them into)
                        // Select mode: what's ticked, and what to do with it
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: ServerStore.selecting ? selBar.implicitHeight : 0
                            Layout.topMargin: ServerStore.selecting ? 0 : -Tokens.space.s12
                            visible: Layout.preferredHeight > 0.5
                            clip: true
                            opacity: ServerStore.selecting ? 1 : 0
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                            Behavior on Layout.topMargin { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                            Behavior on opacity { NumberAnimation { duration: Anim.fast } }
                            Rectangle {
                                id: selBar
                                width: parent.width
                                implicitHeight: selRow.implicitHeight + 2 * Tokens.space.s8
                                radius: Tokens.radius.lg
                                color: Colors.alpha(Colors.accent, 0.10)
                                border.width: 1
                                border.color: Colors.alpha(Colors.accent, 0.35)
                                RowLayout {
                                    id: selRow
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.space.s12
                                    anchors.rightMargin: Tokens.space.s8
                                    spacing: Tokens.space.s6
                                    Text {
                                        text: "󰄲  " + (ServerStore.selection.length === 0 ? "Click servers to select them"
                                                       : ServerStore.selection.length + (ServerStore.selection.length === 1 ? " server selected" : " servers selected"))
                                        color: Colors.ink; font.pixelSize: Tokens.font.body; font.bold: true; font.family: Properties.fontFamily
                                    }
                                    Item { implicitWidth: Tokens.space.s6 }
                                    ActionButton { implicitHeight: 28; variant: "ghost"; text: "All shown"; tooltip: "Ctrl+A"; onClicked: ServerStore.selectOnly(win.shownActive.map(s => s.name)) }
                                    ActionButton { implicitHeight: 28; variant: "ghost"; text: "With updates"
                                                   onClicked: ServerStore.selectOnly(win.shownActive.filter(s => updateDialog.needs(s.name, "all")).map(s => s.name)) }
                                    ActionButton { implicitHeight: 28; variant: "ghost"; text: "Clear"; interactive: ServerStore.selection.length > 0; onClicked: ServerStore.selectOnly([]) }
                                    Item { Layout.fillWidth: true }
                                    ActionButton { implicitHeight: 28; icon: "󰑓"; text: "Scan"; interactive: ServerStore.selection.length > 0
                                                   onClicked: ServerRuns.scanAll(ServerStore.selection.slice()) }
                                    ActionButton { implicitHeight: 28; icon: "󰆍"; text: "Command…"; interactive: ServerStore.selection.length > 0
                                                   onClicked: commandDialog.start(ServerStore.selection.slice()) }
                                    ActionButton { implicitHeight: 28; icon: "󰚰"; text: "Update…"; variant: "primary"; interactive: ServerStore.selection.length > 0
                                                   onClicked: updateDialog.start("custom", ServerStore.selection) }
                                    IconButton { implicitWidth: 28; implicitHeight: 28; icon: "󰅖"; tooltip: "Done  (Esc)"; onClicked: ServerStore.selecting = false }
                                }
                            }
                        }

                        Banner {
                            Layout.fillWidth: true
                            visible: ServerStore.error !== ""
                            tone: "error"
                            text: ServerStore.error + "  (fix the file by hand; nothing is saved until it reads again)"
                        }

                        // ── the groups, and the details pane on the right ──
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 0
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            EmptyState {
                                anchors.centerIn: parent
                                visible: ServerStore.loaded && ServerStore.servers.length === 0
                                icon: "󰒋"
                                text: "No servers yet"
                                hint: ServerStore.exists ? "Add your first one" : "Add one, or run  manage-svs.sh migrate  to bring over the servers of svs.conf"
                                actionText: "Add server"
                                onAction: editor.start(null)
                            }
                            EmptyState {
                                anchors.centerIn: parent
                                visible: ServerStore.servers.length > 0 && win.matches === 0
                                icon: "󰍉"
                                text: "No matching servers"
                                actionText: "Clear the search"
                                onAction: { search.text = ""; win.filter = "all" }
                            }

                            Flickable {
                                id: flick
                                anchors.fill: parent
                                contentHeight: sections.implicitHeight + Tokens.space.s16
                                clip: true
                                // a mouse drag moves a card onto a group (wheel / touchpad / scrollbar scroll)
                                interactive: false
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: SlimScrollBar {}
                                SmoothWheel { flick: flick; step: 140 }

                                ColumnLayout {
                                    id: sections
                                    width: flick.width - 14
                                    spacing: Tokens.space.s14

                                    Repeater {
                                        model: ServerStore.groups
                                        GroupSection {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            gid: modelData.id
                                            title: modelData.name
                                            icon: modelData.icon
                                            editable: true
                                            shownEmpty: !win.searching
                                            servers: ServerStore.ordered(ServerStore.active.filter(s => s.groups.includes(modelData.id)), modelData.id)
                                            reordering: win.reordering && win.dragOver === modelData.id
                                            dropBefore: win.dragBefore
                                            shown: s => win.shown(s)
                                            animateMoves: !drawer.resizing
                                            onEdit: s => win.details(s.name)
                                            onCardMenu: (s, item, x, y) => win.cardMenu(s, item, x, y)
                                            onGroupMenu: (item, x, y) => win.groupMenu(modelData, item, x, y)
                                            dragName: win.dragName
                                            hot: win.dragName !== "" && win.dragOver === modelData.id && win.dragFrom !== modelData.id
                                            onCardDragStarted: (s, p, g) => win.dragStart(s, modelData.id, p, g)
                                            onCardDragMoved: p => win.dragMove(p)
                                            onCardDragEnded: win.dragEnd()
                                            onUpdateRequested: (names, item) => win.updateMenu(item, item.width / 2, item.height, names)
                                        }
                                    }
                                    GroupSection {
                                        Layout.fillWidth: true
                                        gid: "__ungrouped"
                                        dragName: win.dragName
                                        hot: win.dragName !== "" && win.dragOver === gid && win.dragFrom !== gid
                                        shownEmpty: false
                                        // while a card from a group is dragged: a place to drop it out of its group
                                        visible: visibleServers.length > 0 || (win.dragName !== "" && !win.dragFrom.startsWith("__"))
                                        onCardDragStarted: (s, p, g) => win.dragStart(s, gid, p, g)
                                        onCardDragMoved: p => win.dragMove(p)
                                        onCardDragEnded: win.dragEnd()
                                        title: ServerStore.groups.length ? "Ungrouped" : "Servers"
                                        icon: "󰒋"
                                        servers: ServerStore.ordered(ServerStore.active.filter(s => !s.groups.some(g => ServerStore.groupMap[g])), "__ungrouped")
                                        reordering: win.reordering && win.dragOver === gid
                                        dropBefore: win.dragBefore
                                        shown: s => win.shown(s)
                                        animateMoves: !drawer.resizing
                                        onEdit: s => win.details(s.name)
                                        onCardMenu: (s, item, x, y) => win.cardMenu(s, item, x, y)
                                        onUpdateRequested: (names, item) => win.updateMenu(item, item.width / 2, item.height, names)
                                    }
                                    GroupSection {
                                        Layout.fillWidth: true
                                        gid: "__archived"
                                        dragName: win.dragName
                                        hot: win.dragName !== "" && win.dragOver === gid && win.dragFrom !== gid
                                        // an empty Archived still shows while dragging: something to drop on
                                        visible: visibleServers.length > 0 || win.dragName !== ""
                                        onCardDragStarted: (s, p, g) => win.dragStart(s, gid, p, g)
                                        onCardDragMoved: p => win.dragMove(p)
                                        onCardDragEnded: win.dragEnd()
                                        title: "Archived"
                                        icon: "󰀼"
                                        servers: ServerStore.archived
                                        shown: s => win.shown(s)
                                        animateMoves: !drawer.resizing
                                        onEdit: s => win.details(s.name)
                                        onCardMenu: (s, item, x, y) => win.cardMenu(s, item, x, y)
                                    }
                                }
                            }
                        }
                            ServerDrawer {
                                id: drawer
                                Layout.fillHeight: true
                                // its full width, never squeezed by the cards next to it
                                Layout.preferredWidth: implicitWidth
                                Layout.minimumWidth: implicitWidth
                                Layout.maximumWidth: implicitWidth
                                // the cards keep at least ~one column
                                maxWidth: Math.max(360, win.width / zoomArea.zoom - 420)
                                onEdit: s => editor.start(s)
                                onUpdateRequested: (names, item) => win.updateMenu(item, item.width / 2, item.height, names)
                                onCommand: names => commandDialog.start(names)
                                onMenu: (s, item, x, y) => win.cardMenu(s, item, x, y)
                                onConfirmDelete: (t, body, fn) => confirm.ask(t, body, "Delete", fn)
                                onRebootRequested: s => win.askReboot(s)
                                onHistoryRequested: n => historyDialog.start(n)
                                onPveSetupRequested: n => pveDialog.start(n)
                                onLogRequested: (t, f) => logDialog.start(t, f)
                                onContainerLogRequested: (n, c) => ServerStore.containerLog(n, c)
                                // says what goes down, then restarts just those (the script's --restart-pulled)
                                onRestartPulledRequested: (s, names) => confirm.ask("Restart " + names.length + (names.length === 1 ? " container" : " containers") + " on " + s.name + "?",
                                    names.join(", ") + "\n" + (names.length === 1 ? "It goes" : "They go") + " down for a moment and come back on the new image. Health checks run before and after"
                                    + (s.guest && !s.noSnapshot && ServerStore.snapshotMode !== "off" ? ", and a snapshot is taken on " + s.guest.node + " first" : "") + ". The server itself isn't rebooted.",
                                    "Restart", () => ServerRuns.start("update", [s.name], { only: "containers", restartPulled: true, reboot: "none",
                                                                                           containers: names.map(n => s.name + ":" + n) }, "alongside"))
                            }
                        }

                        RunPanel {
                            Layout.fillWidth: true
                            open: win.showRun
                            onCloseRequested: win.showRun = false
                            onOpenRequested: win.showRun = true
                            onAbortRequested: win.abortRun()
                            onRetryRequested: names => updateDialog.start(ServerRuns.run?.opts?.only === "security" ? "security" : "all", names)
                            onLogRequested: (t, f) => logDialog.start(t, f)
                            onContainerLogRequested: (n, c) => ServerStore.containerLog(n, c)
                            onDetailsRequested: n => drawer.show(n)
                            onHistoryRequested: historyDialog.start("")
                            maxHeight: Math.max(240, win.height / zoomArea.zoom - 320)
                        }
                    }

                    // the card being dragged: tilted, follows the pointer; a drop on a group
                    // pops it in, anywhere else it shrinks back
                    Item {
                        id: ghost
                        property string label: ""
                        property bool flying: false
                        width: 230; height: 48
                        x: win.dragAt.x - win.dragGrab.x
                        y: win.dragAt.y - win.dragGrab.y
                        visible: flying
                        z: 50
                        function start() { label = win.dragName; dropAnim.stop(); flying = true; opacity = 1; scale = 1.04; rotation = 2.5 }
                        function finish(ok) { dropAnim.ok = ok; dropAnim.restart() }
                        Behavior on rotation { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
                        SequentialAnimation {
                            id: dropAnim
                            property bool ok: false
                            PropertyAction { target: ghost; property: "rotation"; value: 0 }
                            NumberAnimation { target: ghost; property: "scale"; to: dropAnim.ok ? 1.12 : 0.9; duration: Anim.fast; easing.type: Anim.standard }
                            ParallelAnimation {
                                NumberAnimation { target: ghost; property: "scale"; to: dropAnim.ok ? 0.6 : 0.8; duration: Anim.normal; easing.type: dropAnim.ok ? Anim.pop : Anim.exit }
                                NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: Anim.normal; easing.type: Anim.exit }
                            }
                            PropertyAction { target: ghost; property: "flying"; value: false }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radius.lg
                            color: Colors.alpha(Colors.background, 0.95)
                            border.width: 1.5
                            border.color: win.dragOver !== "" && win.dragOver !== win.dragFrom ? Colors.accent : Properties.cardBorder
                            Behavior on border.color { ColorAnimation { duration: Anim.fast } }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space.s12
                            anchors.rightMargin: Tokens.space.s12
                            spacing: Tokens.space.s8
                            Text { text: "󰒋"; color: Colors.accent; font.pixelSize: Tokens.font.subtitle; font.family: Properties.fontFamily }
                            Text { Layout.fillWidth: true; text: ghost.label; color: Colors.ink; font.pixelSize: Tokens.font.body; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight }
                        }
                    }

                    PopupMenu { id: menu; parent: bg }
                    UpdateDialog { id: updateDialog }
                    CommandDialog { id: commandDialog }
                    TransferDialog { id: transfer }
                    ServerEditor { id: editor; anchors.fill: parent; onPveSetupRequested: n => pveDialog.start(n) }
                    PveDialog { id: pveDialog; anchors.fill: parent }
                    GroupDialog { id: groupDialog; anchors.fill: parent }
                    HistoryDialog {
                        id: historyDialog
                        anchors.fill: parent
                        onLogRequested: (t, f) => logDialog.start(t, f)
                        onCheckRequested: n => ServerRuns.start("check", [n], {}, "alongside")
                        onContainerLogRequested: (n, c) => ServerStore.containerLog(n, c)
                        onDetailsRequested: n => { historyDialog.close(); drawer.show(n) }
                    }
                    LogDialog { id: logDialog; anchors.fill: parent }
                    ConfirmDialog { id: confirm; anchors.fill: parent }
                }
            }
        }
    }
}
