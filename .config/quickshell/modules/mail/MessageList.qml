import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../calendar"
import "MailIcons.js" as I

// The middle column: folder title, quick filter bar (search + unread / starred /
// attachments), and the messages: as conversations or one by one, under day headers.
// Hovering a row shows archive / delete / read / star.
ColumnLayout {
    id: root

    property string view: "unified:inbox"
    property string title: ""
    property string selected: ""            // row key (conversation or message id)
    signal opened(var row)                  // { key, msgs, … } or a draft { draft }
    signal draftOpened(var draft)

    property alias query: search.text
    property bool fUnread: false
    property bool fFlagged: false
    property bool fAttachments: false
    property string serverNote: ""
    property bool searching: false
    readonly property bool filtering: query.trim() !== "" || fUnread || fFlagged || fAttachments

    function focusSearch() { search.forceActiveFocus(); search.selectAll() }
    function clearFilter() { search.text = ""; fUnread = false; fFlagged = false; fAttachments = false; serverNote = "" }
    onViewChanged: { clearFilter(); list.positionViewAtBeginning(); Qt.callLater(enter) }
    // another folder: its first rows come in one after another (like a settings page)
    function enter() {
        for (const c of list.contentItem.children)
            if (c.rowIn && c.index < 10) c.rowIn.restart()
    }

    // minute ticker so "Today" / times stay right
    readonly property double now: { Time.minutes; return Date.now() }

    readonly property bool drafts: view === "local:drafts"
    readonly property var rows: {
        if (drafts) {
            return MailStore.drafts.slice().sort((a, b) => b.saved - a.saved).map((d, i, all) => ({
                key: "draft:" + d.id, draft: d, latest: d.saved,
                group: MailUtil.dayGroup(d.saved, now), head: i === 0 || MailUtil.dayGroup(all[i - 1].saved, now) !== MailUtil.dayGroup(d.saved, now)
            }))
        }
        const f = { unread: fUnread, flagged: fFlagged, attachments: fAttachments, text: query }
        const msgs = MailStore.messagesIn(view).filter(m => MailUtil.matches(m, f))
        const list = MailStore.threaded && !view.startsWith("unified:flagged")
            ? MailUtil.threads(msgs)
            : msgs.map(m => ({ key: m.id, msgs: [m], latest: m.date, last: m, unread: m.seen ? 0 : 1, flagged: !!m.flagged,
                                attachments: m.attachments > 0, subject: m.subject, people: [MailUtil.displayName(m.from)] }))
        let prev = ""
        for (const r of list) {
            r.group = MailUtil.dayGroup(r.latest, now)
            r.head = r.group !== prev
            prev = r.group
        }
        return list
    }
    readonly property var keys: rows.map(r => r.key)

    // keyboard (from the window): the next / previous row, the next unread
    function step(dir) {
        if (rows.length === 0) return
        const i = keys.indexOf(selected)
        const j = i < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, i + dir))
        open(rows[j])
    }
    function nextUnread() {
        const i = keys.indexOf(selected)
        for (let k = 1; k <= rows.length; k++) {
            const r = rows[(i + k + rows.length) % rows.length]
            if (r.unread > 0) { open(r); return }
        }
    }
    function open(r) {
        if (r.draft) { root.draftOpened(r.draft); return }
        root.opened(r)
        list.positionViewAtIndex(keys.indexOf(r.key), ListView.Contain)
    }

    function serverSearch() {
        const q = query.trim()
        if (!q || !view.includes("|") || drafts) return
        searching = true
        serverNote = ""
        MailStore.search(view, q, res => {
            searching = false
            serverNote = res.ok ? (res.uids.length === 0 ? "Nothing on the server either"
                                  : res.uids.length + " on the server" + (res.messages.length ? ", " + res.messages.length + " more loaded" : ""))
                                : res.error
        })
    }

    spacing: 10

    // ── Title ──
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 8
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: root.title
                color: Colors.ink
                font.pixelSize: 22
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: {
                    if (root.drafts) return root.rows.length + (root.rows.length === 1 ? " draft" : " drafts") + " · on this computer"
                    const n = root.rows.reduce((s, r) => s + r.msgs.length, 0)
                    const u = root.rows.reduce((s, r) => s + r.unread, 0)
                    return (root.filtering ? n + " found" : n + (n === 1 ? " message" : " messages")) + (u ? "  ·  " + u + " unread" : "")
                }
                color: Colors.fade(0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
        IconButton {
            visible: !root.drafts && root.rows.some(r => r.unread > 0)
            implicitWidth: 28; implicitHeight: 28; iconSize: 12
            icon: I.check
            tooltip: "Mark all as read"
            onClicked: MailStore.markAllRead(root.view)
        }
    }

    // ── Quick filter ──
    SearchField {
        id: search
        Layout.fillWidth: true
        placeholderText: root.view.includes("|") ? "Search  (Enter: also on the server)" : "Search"
        onAccepted: root.serverSearch()
        onTextChanged: root.serverNote = ""
        Keys.onEscapePressed: { if (text !== "") text = ""; else focus = false }
        Keys.onDownPressed: { root.step(1); focus = false }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: !root.drafts
        FilterChip { icon: I.mail; text: "Unread"; checked: root.fUnread; onToggled: root.fUnread = !root.fUnread }
        FilterChip { icon: I.star; text: "Starred"; checked: root.fFlagged; onToggled: root.fFlagged = !root.fFlagged }
        FilterChip { icon: I.clip; checked: root.fAttachments; onToggled: root.fAttachments = !root.fAttachments
                     ToolTip.visible: hov.hovered; ToolTip.text: "With attachments"; HoverHandler { id: hov } }
        Item { Layout.fillWidth: true }
        Text {
            visible: root.searching || root.serverNote !== ""
            Layout.maximumWidth: 160
            text: root.searching ? "Searching the server…" : root.serverNote
            color: Colors.fade(0.45)
            font.pixelSize: 10
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }

    // ── Messages ──
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 4
            model: root.rows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: CalScrollBar {}
            SmoothWheel { flick: list; step: 140 }
            reuseItems: true
            cacheBuffer: 1600          // rows are built ahead, so scrolling doesn't stall on new ones

            delegate: Column {
                id: row
                required property var modelData
                required property int index
                readonly property var r: modelData
                readonly property var m: r.draft ? null : r.last
                readonly property bool sel: root.selected === r.key
                width: ListView.view.width - 8
                x: 2
                transformOrigin: Item.Top
                property alias rowIn: rowIn
                SequentialAnimation {
                    id: rowIn
                    PropertyAction { target: row; property: "opacity"; value: 0 }
                    PauseAnimation { duration: row.index * 35 }
                    ParallelAnimation {
                        NumberAnimation { target: row; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        NumberAnimation { target: row; property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
                    }
                }

                // day header
                Text {
                    visible: row.r.head
                    width: parent.width
                    height: visible ? 28 : 0
                    leftPadding: 10
                    verticalAlignment: Text.AlignBottom
                    bottomPadding: 5
                    text: row.r.group
                    color: Colors.fade(0.4)
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.1
                    font.capitalization: Font.AllUppercase
                    font.family: Properties.fontFamily
                }

                Rectangle {
                    id: card
                    width: parent.width
                    height: 74
                    radius: 10
                    color: row.sel ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16)
                         : rowHover.hovered ? Colors.fade(0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }

                    // hover of the whole row, the action buttons included (the row's own
                    // MouseArea loses it over them: the buttons would hide, show, hide, …)
                    HoverHandler { id: rowHover }
                    readonly property bool actions: rowHover.hovered && !row.r.draft

                    // unread dot
                    Rectangle {
                        visible: (row.r.unread ?? 0) > 0
                        x: 5; y: 18
                        width: 7; height: 7; radius: 4
                        color: Colors.color6
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 10
                        spacing: 10

                        Avatar {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 10
                            size: 34
                            person: row.r.draft ? { name: "Draft", email: "" } : row.m.from
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: row.r.draft ? "To: " + ((row.r.draft.to ?? []).map(a => MailUtil.displayName(a)).join(", ") || "—")
                                        : row.r.people.slice(-3).join(", ")
                                    color: Colors.ink
                                    font.pixelSize: 12
                                    font.bold: (row.r.unread ?? 0) > 0
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: (row.r.msgs?.length ?? 1) > 1 && !card.actions
                                    implicitWidth: cnt.implicitWidth + 10
                                    implicitHeight: 16
                                    radius: 8
                                    color: Colors.fade(0.08)
                                    Text { id: cnt; anchors.centerIn: parent; text: row.r.msgs?.length ?? ""; color: Colors.fade(0.6)
                                           font.pixelSize: 10; font.family: Properties.fontFamily }
                                }
                                // account color in the unified views
                                Rectangle {
                                    visible: !row.r.draft && root.view.startsWith("unified:") && MailStore.accounts.length > 1 && !card.actions
                                    implicitWidth: 6; implicitHeight: 6; radius: 3
                                    color: MailStore.accountMap[row.m?.account]?.color ?? "transparent"
                                }
                                Text {
                                    visible: !card.actions
                                    text: MailUtil.shortDate(row.r.latest, root.now)
                                    color: (row.r.unread ?? 0) > 0 ? Colors.color6 : Colors.fade(0.45)
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Text {
                                    visible: !!row.m?.answered || !!row.m?.forwarded
                                    text: row.m?.forwarded ? I.forward : I.reply
                                    color: Colors.fade(0.4)
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (row.r.draft ? row.r.draft.subject : row.r.subject) || "(no subject)"
                                    color: Colors.fade((row.r.unread ?? 0) > 0 ? 0.9 : 0.72)
                                    font.pixelSize: 12
                                    font.bold: (row.r.unread ?? 0) > 0
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: !!row.r.attachments
                                    text: I.clip
                                    color: Colors.fade(0.45)
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                }
                                Text {
                                    visible: !!row.r.flagged
                                    text: I.star
                                    color: Colors.yellow
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.r.draft ? (row.r.draft.text || "").replace(/\s+/g, " ").slice(0, 160) : (row.m.preview || " ")
                                color: Colors.fade(0.45)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.open(row.r)
                    }

                    // hover actions
                    Row {
                        opacity: card.actions ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        spacing: 0
                        IconButton {
                            implicitWidth: 24; implicitHeight: 24; iconSize: 12
                            icon: (row.r.unread ?? 0) > 0 ? I.mailOpen : I.mail
                            tooltip: (row.r.unread ?? 0) > 0 ? "Mark as read  (M)" : "Mark as unread  (M)"
                            onClicked: MailStore.markRead(row.r.msgs, (row.r.unread ?? 0) > 0)
                        }
                        IconButton {
                            implicitWidth: 24; implicitHeight: 24; iconSize: 12
                            icon: row.r.flagged ? I.star : I.starOutline
                            tooltip: row.r.flagged ? "Remove star  (S)" : "Star  (S)"
                            onClicked: MailStore.star(row.r.flagged ? row.r.msgs : [row.r.last], !row.r.flagged)
                        }
                        IconButton {
                            implicitWidth: 24; implicitHeight: 24; iconSize: 12
                            icon: I.archive
                            tooltip: "Archive  (A)"
                            onClicked: MailStore.moveTo(row.r.msgs, "archive")
                        }
                        IconButton {
                            implicitWidth: 24; implicitHeight: 24; iconSize: 12
                            icon: I.trash
                            tooltip: "Delete  (Del)"
                            onClicked: MailStore.remove(row.r.msgs)
                        }
                    }
                }
            }
        }

        // empty states
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: root.rows.length === 0
            spacing: 6
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.filtering ? I.search : I.inbox
                color: Colors.fade(0.2)
                font.pixelSize: 34
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.filtering ? "Nothing matches" + (root.view.includes("|") && root.query ? " — press Enter to search the server" : "")
                    : MailStore.accounts.length === 0 ? "No accounts yet" : MailStore.syncing ? "Checking for mail…" : "Nothing here"
                color: Colors.fade(0.45)
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
        }
    }
}
