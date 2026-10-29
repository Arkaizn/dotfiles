import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings"
import "MailIcons.js" as I

// Mail app: sidebar (all inboxes, unread, starred, drafts, each account's
// folders), the message list with the quick filter, and the open conversation.
// Data: services/MailStore.qml, network: scripts/mail/mailsync.py.
//
// Open it with:  qs ipc call mail toggle   (or the "Mail" launcher entry)
// Keys (like Thunderbird): ↑/↓ move · N next unread · R reply · Shift+R reply all
//   F forward · A archive · J junk · Del delete · M read / unread · S star · Ctrl+N new
//   / or Ctrl+F search · F5 check now · Esc close the message
Scope {
    id: root

    // kept across shell reloads (config edits etc.): an open window comes back
    property alias open: persist.open
    property alias view: persist.view
    PersistentProperties {
        id: persist
        reloadableId: "mailWindow"
        property bool open: false
        property string view: "unified:inbox"
    }

    readonly property string windowTitle: "Quickshell Mail"
    function show() {
        if (root.open) Compositor.focusWindow(root.windowTitle)
        root.open = true
    }

    // what to do once the window is there
    property var pending: null               // { compose: to } | { mailto } | { message: id }

    readonly property var api: ({
        open: () => root.show(),
        toggle: () => { root.open = !root.open },
        close: () => root.open = false,
        compose: to => { root.pending = { compose: to ?? "" }; root.show() },
        mailto: url => { root.pending = { mailto: url }; root.show() },
        showMessage: id => { root.pending = { message: id }; root.show() },
        settings: () => { root.pending = { settings: true }; root.show() },
        check: () => MailStore.check(true)
    })
    Component.onCompleted: Panels.register("mail", api)
    Component.onDestruction: Panels.unregister("mail", api)

    IpcHandler {
        target: "mail"
        function open(): void { root.show() }
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
        function check(): void { MailStore.check(true) }
        function compose(to: string): void { root.api.compose(to) }
        function mailto(url: string): void { root.api.mailto(url) }
        function showMessage(id: string): void { root.api.showMessage(id) }
        function settings(): void { root.api.settings() }
        function unread(): string { return String(MailStore.unread) }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: root.windowTitle
            implicitWidth: 1320
            implicitHeight: 820
            minimumSize: Qt.size(860, 540)
            color: "transparent"
            visible: true
            onVisibleChanged: if (!visible) { root.open = false; MailStore.flushUndo() }

            property var row: null                    // the open conversation

            Component.onCompleted: {
                Qt.callLater(takePending)
                MailStore.watch(root.view)
                if (Date.now() - MailStore.lastSync > 60000) MailStore.check()
                if (MailStore.accounts.length === 0) Qt.callLater(() => accountDialog.start())
                keys.forceActiveFocus()
            }
            Connections {
                target: root
                function onPendingChanged() { Qt.callLater(win.takePending) }
                function onViewChanged() { win.row = null; MailStore.watch(root.view); if (root.view.includes("|")) MailStore.check() }
            }
            function takePending() {
                const p = root.pending
                if (!p) return
                root.pending = null
                if (p.settings) settingsDialog.open()
                else if (p.compose !== undefined) composer.compose(p.compose)
                else if (p.mailto !== undefined) {
                    const m = MailUtil.parseMailto(p.mailto)
                    composer.compose(m.to)
                    composer.fCc = m.cc; composer.fBcc = m.bcc; composer.showCc = !!(m.cc || m.bcc)
                    composer.fSubject = m.subject
                    if (m.body) composer.fText = m.body + composer.fText
                } else if (p.message) {
                    const m = MailStore.byId[p.message]
                    if (!m) return
                    root.view = m.folder === MailStore.inboxOf(m.account) ? "unified:inbox" : m.account + "|" + m.folder
                    Qt.callLater(() => {
                        const r = list.rows.find(r => r.msgs?.some(x => x.id === m.id))
                        if (r) list.open(r)
                    })
                }
            }

            readonly property string viewTitle: {
                const v = root.view
                if (v === "unified:inbox") return MailStore.accounts.length > 1 ? "All inboxes" : "Inbox"
                if (v === "unified:unread") return "Unread"
                if (v === "unified:flagged") return "Starred"
                if (v.startsWith("unified:")) {
                    const many = MailStore.activeAccounts.length > 1
                    return ({ sent: many ? "All sent" : "Sent", drafts: many ? "All drafts" : "Drafts", archive: many ? "All archived" : "Archive",
                              trash: many ? "All deleted" : "Trash", junk: many ? "All junk" : "Junk" })[v.slice(8)] ?? v
                }
                if (v === "local:drafts") return "Unsent drafts"
                const i = v.indexOf("|")
                const f = (MailStore.accountMap[v.slice(0, i)]?.folders ?? []).find(f => f.path === v.slice(i + 1))
                return f ? (f.role === "inbox" ? "Inbox" : f.name) : v.slice(i + 1)
            }

            function act(fn) { if (win.row && win.row.msgs) fn(win.row.msgs.map(m => MailStore.byId[m.id] ?? m)) }
            function latest() { return win.row?.msgs ? (MailStore.byId[win.row.msgs[win.row.msgs.length - 1].id] ?? win.row.msgs[win.row.msgs.length - 1]) : null }
            // after archive / delete: on to the next one, like Thunderbird
            function removeAndNext(fn) {
                if (!win.row) return
                const i = list.keys.indexOf(win.row.key)
                act(fn)
                Qt.callLater(() => {
                    const rows = list.rows
                    win.row = rows.length ? rows[Math.min(i, rows.length - 1)] : null
                    if (win.row) list.selected = win.row.key
                })
            }

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: Compositor.appRadius
                // settings: mail → solid background (no transparency behind the mail)
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, MailStore.solid ? 1 : 0.86)

                Item {
                    id: keys
                    focus: true
                    Keys.onPressed: event => {
                        if (composer.shown || accountDialog.shown || folderDialog.shown || settingsDialog.shown || viewer.shown || transfer.shown) return
                        const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
                        if (ctrl) {
                            if (event.key === Qt.Key_Z) MailStore.undo()
                            else if (event.key === Qt.Key_N) composer.compose("")
                            else if (event.key === Qt.Key_F) list.focusSearch()
                            else if (event.key === Qt.Key_A) list.pickAll()
                            else if (event.key === Qt.Key_R && shift) { if (win.latest()) composer.reply(win.latest(), true) }
                            else if (event.key === Qt.Key_R) { if (win.latest()) composer.reply(win.latest(), false) }
                            else return
                            event.accepted = true
                            return
                        }
                        // several rows picked: the keys act on all of them
                        if (list.pickedRows.length > 0) {
                            const a = ({ [Qt.Key_A]: "archive", [Qt.Key_J]: "junk", [Qt.Key_Delete]: "delete", [Qt.Key_M]: "read", [Qt.Key_S]: "star" })[event.key]
                            if (a) { list.batch(a); event.accepted = true; return }
                            if (event.key === Qt.Key_Escape) { list.clearPicks(); event.accepted = true; return }
                        }
                        switch (event.key) {
                        case Qt.Key_Down: list.step(1); break
                        case Qt.Key_Up: list.step(-1); break
                        case Qt.Key_N: list.nextUnread(); break
                        case Qt.Key_Slash: list.focusSearch(); break
                        case Qt.Key_F5: MailStore.check(true); break
                        case Qt.Key_R: if (win.latest()) composer.reply(win.latest(), shift); break
                        case Qt.Key_F: if (win.latest()) composer.forward(win.latest()); break
                        case Qt.Key_A: win.removeAndNext(l => MailStore.moveTo(l, "archive")); break
                        case Qt.Key_J: win.removeAndNext(l => MailStore.moveTo(l, "junk")); break
                        case Qt.Key_Delete: win.removeAndNext(l => MailStore.remove(l)); break
                        case Qt.Key_M: win.act(l => MailStore.markRead(l, l.some(m => !m.seen))); break
                        case Qt.Key_S: win.act(l => MailStore.star(l.some(m => m.flagged) ? l : [l[l.length - 1]], !l.some(m => m.flagged))); break
                        case Qt.Key_Escape: if (!win.row) return; win.row = null; list.selected = ""; break
                        default: return
                        }
                        event.accepted = true
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    // ── Sidebar ──
                    // its width: dragged on the line between it and the list (Settings.mail.sidebarWidth)
                    Rectangle {
                        id: side
                        property real dragWidth: -1
                        readonly property real savedWidth: Settings.mail.sidebarWidth ?? 230
                        Layout.preferredWidth: Math.max(180, Math.min(dragWidth >= 0 ? dragWidth : savedWidth, 400))
                        Layout.fillHeight: true
                        radius: Math.max(6, Compositor.appRadius - 2)
                        color: Colors.card
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 10
                                    Text { text: I.mail; color: Colors.color6; font.pixelSize: 22; font.family: Properties.fontFamily }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Mail"
                                        color: Colors.ink
                                        font.pixelSize: 18
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                }
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) bg.Window.window.startSystemMove()
                                }
                            }

                            ActionButton {
                                Layout.fillWidth: true
                                implicitHeight: Properties.buttonHeight + 4
                                icon: I.draft
                                text: "New message"
                                primary: true
                                onClicked: composer.compose("")
                            }

                            Sidebar {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: 6
                                view: root.view
                                onPicked: v => root.view = v
                                onAccountMenu: id => accountDialog.edit(MailStore.accountMap[id])
                                onNewFolder: (acc, parent) => folderDialog.start(acc, parent)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    text: MailStore.syncing ? "Checking…"
                                        : Object.keys(MailStore.errors).length ? "󰀦 " + Object.values(MailStore.errors)[0]
                                        : MailStore.lastSync ? "Checked " + Format.hm(MailStore.lastSync) : ""
                                    color: Object.keys(MailStore.errors).length && !MailStore.syncing ? Colors.red : Colors.fade(0.4)
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                IconButton {
                                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                                    icon: I.plus
                                    tooltip: "Add an account"
                                    onClicked: accountDialog.start()
                                }
                                IconButton {
                                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                                    icon: I.cog
                                    tooltip: "Mail settings"
                                    onClicked: settingsDialog.open()
                                }
                                IconButton {
                                    id: refreshButton
                                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                                    icon: I.refresh
                                    tooltip: "Check now  (F5)"
                                    interactive: !MailStore.syncing && MailStore.activeAccounts.length > 0
                                    RotationAnimation on rotation {
                                        running: MailStore.syncing
                                        loops: Animation.Infinite
                                        from: 0; to: 360; duration: 900
                                        onStopped: refreshButton.rotation = 0
                                    }
                                    onClicked: MailStore.check(true)
                                }
                            }
                        }
                    }

                    // the line between sidebar and list: drag it to resize, double-click resets
                    Item {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 6
                        Layout.leftMargin: -10
                        Layout.rightMargin: -10
                        Rectangle {
                            anchors.centerIn: parent
                            width: 3
                            height: 48
                            radius: 1.5
                            color: Colors.fade(sideSplit.pressed ? 0.7 : sideSplit.containsMouse ? 0.45 : 0)
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        MouseArea {
                            id: sideSplit
                            anchors.fill: parent
                            anchors.leftMargin: -4
                            anchors.rightMargin: -4
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.SizeHorCursor
                            property real startX: 0
                            property real startW: 0
                            onPressed: m => { startX = mapToItem(null, m.x, 0).x; startW = side.width }
                            onPositionChanged: m => { if (pressed) side.dragWidth = Math.max(180, Math.min(400, startW + mapToItem(null, m.x, 0).x - startX)) }
                            onReleased: {
                                if (side.dragWidth >= 0) Settings.set("mail", "sidebarWidth", Math.round(side.dragWidth))
                                side.dragWidth = -1
                            }
                            onDoubleClicked: { side.dragWidth = -1; Settings.set("mail", "sidebarWidth", 230) }
                        }
                    }

                    // ── Messages ──
                    // the list's width: dragged on the line between it and the message (Settings.mail.listWidth)
                    MessageList {
                        id: list
                        Layout.fillWidth: false            // a layout fills by default
                        // dragging: follows the pointer; else the saved width (never so wide the message gets squeezed)
                        property real dragWidth: -1
                        readonly property real savedWidth: Settings.mail.listWidth ?? 380
                        Layout.preferredWidth: Math.max(260, Math.min(dragWidth >= 0 ? dragWidth : savedWidth, bg.width - 700))
                        Layout.fillHeight: true
                        view: root.view
                        title: win.viewTitle
                        selected: win.row?.key ?? ""
                        onOpened: r => { win.row = r; keys.forceActiveFocus() }
                        onDraftOpened: d => composer.openDraft(d)
                        onPickedGone: ks => { if (win.row && ks.includes(win.row.key)) { win.row = null; list.selected = "" } }
                    }

                    // the line between list and message: drag it to resize, double-click resets
                    Item {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 6
                        Layout.leftMargin: -10
                        Layout.rightMargin: -10
                        Rectangle {
                            anchors.centerIn: parent
                            width: 3
                            height: 48
                            radius: 1.5
                            color: Colors.fade(split.pressed ? 0.7 : split.containsMouse ? 0.45 : 0)
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        MouseArea {
                            id: split
                            anchors.fill: parent
                            anchors.leftMargin: -4
                            anchors.rightMargin: -4
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.SizeHorCursor
                            property real startX: 0
                            property real startW: 0
                            onPressed: m => { startX = mapToItem(null, m.x, 0).x; startW = list.width }
                            onPositionChanged: m => { if (pressed) list.dragWidth = Math.max(260, Math.min(720, startW + mapToItem(null, m.x, 0).x - startX)) }
                            onReleased: {
                                if (list.dragWidth >= 0) Settings.set("mail", "listWidth", Math.round(list.dragWidth))
                                list.dragWidth = -1
                            }
                            onDoubleClicked: { list.dragWidth = -1; Settings.set("mail", "listWidth", 380) }
                        }
                    }

                    // ── Reading ──
                    Reader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        row: win.row
                        onReply: (m, all) => composer.reply(m, all)
                        onForward: m => composer.forward(m)
                        onViewAttachment: (m, atts, i) => viewer.show(m, atts, i)
                        onClosed: { win.row = null; keys.forceActiveFocus() }
                    }
                }

                // a change the server refused
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 24
                    visible: MailStore.lastError !== ""
                    width: Math.min(parent.width - 80, errText.implicitWidth + 60)
                    height: 40
                    radius: 20
                    color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                    border.width: 1
                    border.color: Colors.red
                    z: 50
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 6
                        Text { id: errText; Layout.fillWidth: true; text: "󰀦  " + MailStore.lastError; color: Colors.ink
                               font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideRight }
                        IconButton { implicitWidth: 28; implicitHeight: 28; icon: I.close; onClicked: MailStore.lastError = "" }
                    }
                }

                // archived / deleted: undo for a few seconds
                Rectangle {
                    id: undoToast
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: MailStore.lastError !== "" ? 74 : 24
                    // fades and grows in / out (the text stays while it goes)
                    readonly property bool on: MailStore.undoable !== null
                    property string label: ""
                    Connections { target: MailStore; function onUndoableChanged() { if (MailStore.undoable) undoToast.label = MailStore.undoable.label } }
                    visible: opacity > 0
                    opacity: on ? 1 : 0
                    scale: on ? 1 : 0.92
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    width: undoRow.implicitWidth + 30
                    height: 42
                    radius: 21
                    color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.panelBorder
                    z: 50
                    RowLayout {
                        id: undoRow
                        anchors.centerIn: parent
                        spacing: 10
                        Text { text: undoToast.label; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                        ActionButton { icon: I.back; text: "Undo  (Ctrl+Z)"; onClicked: MailStore.undo() }
                    }
                }

                Composer { id: composer; onClosed: keys.forceActiveFocus() }
                Viewer { id: viewer; onShownChanged: if (!shown) keys.forceActiveFocus() }
                AccountTransfer { id: transfer; onClosed: keys.forceActiveFocus() }
                AccountDialog { id: accountDialog; onClosed: keys.forceActiveFocus() }
                FolderDialog { id: folderDialog; onClosed: keys.forceActiveFocus(); onCreated: v => root.view = v }
                MailSettings {
                    id: settingsDialog
                    onClosed: keys.forceActiveFocus()
                    onEditAccount: a => accountDialog.edit(a)
                    onTransfer: mode => transfer.start(mode)
                }
            }
        }
    }
}
