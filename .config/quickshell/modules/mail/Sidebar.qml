import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../calendar"
import "MailIcons.js" as I

// Folder list: the unified views, local drafts, then each account with its folders.
// Looks like the settings app's sidebar: the open folder has one highlight that
// slides from folder to folder, hover a lighter version of it.
Flickable {
    id: root

    property string view: "unified:inbox"
    signal picked(string view)
    signal accountSettings(string id)                   // the account's page in the mail settings
    signal newFolder(string account, string parent)     // from the right-click menus

    // (first: the rows above Entry use it)
    // hover: a lighter version of the highlight (like the settings app's sidebar)
    component HoverFace: Rectangle {
        property bool shown: false
        z: -2
        anchors.fill: parent
        radius: Properties.radius + 2
        border.width: 1.5
        border.color: Colors.fade(0.14)
        gradient: ButtonGradient { hovered: false }
        opacity: shown ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: CalScrollBar { id: bar }
    SmoothWheel { flick: root; step: 100 }       // like the settings app's page list

    // the open folder's highlight (the Entries point it at themselves)
    Rectangle {
        id: pick
        property Item target: null
        readonly property bool on: target !== null && target.current && target.visible
        // its x / y and every parent's up to the list: follows folders folding, the list rebuilt
        readonly property point at: {
            let x = 0, y = 0
            for (let it = target; it && it !== root.contentItem; it = it.parent) { x += it.x; y += it.y }
            return Qt.point(x, y)
        }
        x: at.x
        y: at.y
        width: target?.width ?? 0
        height: target?.height ?? 0
        radius: Properties.radius + 2
        border.width: 1.5
        border.color: Colors.fade(0.24)
        gradient: ButtonGradient { hovered: true }
        opacity: on ? 1 : 0
        scale: travel.running ? 0.97 : 1
        onTargetChanged: if (opacity > 0) travel.restart()
        Timer { id: travel; interval: 180 }
        readonly property bool slides: opacity > 0
        Behavior on x { enabled: pick.slides; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
        Behavior on y { enabled: pick.slides; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
        Behavior on width { enabled: pick.slides; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    ColumnLayout {
        id: col
        // room for the scrollbar when there is one: it would cover the counts and the pin
        width: root.width - (bar.visible ? bar.width - 2 : 0)
        spacing: 1

        Label { text: "FAVORITES" }
        // the unified views switched on in the settings (Mail → Favorites)
        Repeater {
            model: MailStore.favorites
            Entry {
                required property string modelData
                readonly property bool many: MailStore.activeAccounts.length > 1
                v: "unified:" + modelData
                glow: pick
                current: root.view === v
                onActivated: root.picked(v)
                icon: modelData === "unread" ? I.mail : modelData === "flagged" ? I.star : I.role(modelData)
                label: ({ inbox: many ? "All inboxes" : "Inbox", unread: "Unread", flagged: "Starred",
                          sent: many ? "All sent" : "Sent", drafts: many ? "All drafts" : "Drafts",
                          archive: many ? "All archived" : "Archive", trash: many ? "All deleted" : "Trash",
                          junk: many ? "All junk" : "Junk" })[modelData]
                count: modelData === "inbox" || modelData === "unread" ? MailStore.unread : 0
                muted: modelData !== "inbox"
            }
        }
        Entry { v: "local:drafts"; glow: pick; current: root.view === v; onActivated: root.picked(v); icon: I.draft; label: "Unsent drafts"; visible: MailStore.drafts.length > 0
                count: MailStore.drafts.length; muted: true }
        // pinned folders (the pin on a folder's row)
        Repeater {
            model: MailStore.pinnedViews
            Entry {
                required property var modelData
                v: modelData.view
                glow: pick
                current: root.view === v
                onActivated: root.picked(v)
                icon: I.role(modelData.folder.role)
                label: modelData.folder.role === "inbox" ? "Inbox" : modelData.folder.name
                hint: MailStore.activeAccounts.length > 1 ? MailStore.accountLabel(modelData.account) : ""
                dot: MailStore.activeAccounts.length > 1 ? (modelData.account.color ?? "") : ""
                count: MailStore.unreadIn(modelData.account.id, modelData.folder.path)
                muted: modelData.folder.role !== "inbox"
                pinnable: true
                pinned: true
                onPinToggled: MailStore.togglePin(modelData.account.id, modelData.folder.path)
            }
        }

        Label { text: "ACCOUNTS"; Layout.topMargin: 12; visible: MailStore.accounts.length > 0 }
        Repeater {
            model: MailStore.accounts
            ColumnLayout {
                id: acc
                required property var modelData
                readonly property bool on: modelData.enabled !== false
                readonly property string error: MailStore.errors[modelData.id] ?? ""
                readonly property bool collapsed: modelData.collapsed === true
                readonly property int unread: on ? MailStore.unreadIn(modelData.id, MailStore.inboxOf(modelData.id)) : 0
                readonly property string label: MailStore.accountLabel(modelData)
                Layout.fillWidth: true
                spacing: 1

                // the account: its color, name, new mail; click folds it, right-click: its menu
                Rectangle {
                    id: head
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 38
                    radius: Properties.radius + 2
                    color: "transparent"
                    HoverFace { shown: headMouse.containsMouse }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 8
                        spacing: 8
                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: 10
                            color: acc.modelData.color || Colors.color6
                            opacity: acc.on ? 1 : 0.35
                            Text {
                                anchors.centerIn: parent
                                text: acc.label.charAt(0).toUpperCase()
                                color: Colors.background
                                font.pixelSize: 10
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: acc.label
                                color: acc.on ? Colors.ink : Colors.fade(0.4)
                                font.pixelSize: 12
                                font.bold: true
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: acc.on ? acc.modelData.email : "Off — not checked"
                                color: Colors.fade(0.38)
                                font.pixelSize: 9
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: acc.error !== ""
                            text: I.alert
                            color: Colors.red
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                            HoverHandler { id: errHover }
                            ToolTip.visible: errHover.hovered
                            ToolTip.text: acc.error
                        }
                        // new mail in its inbox: also seen while it's folded
                        Rectangle {
                            visible: acc.unread > 0
                            implicitWidth: Math.max(18, unreadText.implicitWidth + 10)
                            implicitHeight: 16
                            radius: 8
                            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18)
                            Text {
                                id: unreadText
                                anchors.centerIn: parent
                                text: acc.unread > 999 ? "999+" : acc.unread
                                color: Colors.color6
                                font.pixelSize: 10
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                        }
                        Text {
                            visible: acc.on
                            text: I.down
                            rotation: acc.collapsed ? -90 : 0
                            Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            color: Colors.fade(headMouse.containsMouse ? 0.6 : 0.3)
                            font.pixelSize: 13
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        id: headMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: m => {
                            if (m.button === Qt.RightButton) root.accountContext(acc.modelData, head, m.x, m.y)
                            else if (acc.on) MailStore.setAccount(acc.modelData.id, { collapsed: !acc.collapsed })
                        }
                    }
                }

                Repeater {
                    model: acc.on && !acc.collapsed ? root.ordered(acc.modelData.folders ?? []) : []
                    ColumnLayout {
                        id: fRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 1
                        // where the standard folders end and the own ones begin
                        Rectangle {
                            visible: fRow.modelData.firstOwn === true
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            implicitHeight: 1
                            color: Colors.fade(0.07)
                        }
                        Entry {
                            id: folderEntry
                            readonly property var f: fRow.modelData.folder
                            v: acc.modelData.id + "|" + f.path
                            glow: pick
                            current: root.view === v
                            onActivated: root.picked(v)
                            icon: I.role(f.role)
                            label: f.role === "inbox" ? "Inbox" : f.name
                            indent: Math.min(3, f.depth ?? 0)
                            count: ["sent", "drafts", "trash", "junk", "all"].includes(f.role) ? 0
                                 : MailStore.unreadIn(acc.modelData.id, f.path) || (f.unread ?? 0)
                            muted: f.role !== "inbox"
                            pinnable: true
                            pinned: MailStore.isPinned(acc.modelData.id, f.path)
                            onPinToggled: MailStore.togglePin(acc.modelData.id, f.path)
                            onContext: (x, y) => root.folderContext(acc.modelData, f, folderEntry, x, y)
                        }
                    }
                }
            }
        }
    }

    // standard folders first (inbox, drafts, sent, archive, junk, trash), each with
    // its subfolders, then the own ones in the server's order
    // → [{ folder, firstOwn }]
    readonly property var roleOrder: ["inbox", "drafts", "sent", "archive", "junk", "trash", "all"]
    function ordered(folders) {
        const blocks = []
        for (const f of folders) {
            if ((f.depth ?? 0) === 0 || blocks.length === 0) blocks.push([f])
            else blocks[blocks.length - 1].push(f)
        }
        const rank = b => { const i = roleOrder.indexOf(b[0].role); return i < 0 ? 99 : i }
        const sorted = blocks.map((b, i) => ({ b, i })).sort((x, y) => rank(x.b) - rank(y.b) || x.i - y.i).map(x => x.b)
        const out = []
        let seenOwn = false, seenRole = false
        for (const b of sorted) {
            const own = rank(b) === 99
            b.forEach((f, j) => out.push({ folder: f, firstOwn: own && !seenOwn && seenRole && j === 0 }))
            if (own) seenOwn = true; else seenRole = true
        }
        return out
    }

    // ── right-click menus ──
    MailMenu { id: menu; parent: root }
    function folderContext(a, f, item, x, y) {
        const pinned = MailStore.isPinned(a.id, f.path)
        menu.show(item, x, y, f.role === "inbox" ? "Inbox" : f.name, [
            { icon: I.open, label: "Open", run: () => root.picked(a.id + "|" + f.path) },
            { icon: pinned ? "󰤰" : "󰐃", label: pinned ? "Remove from favorites" : "Pin to favorites", run: () => MailStore.togglePin(a.id, f.path) },
            { sep: true },
            { icon: I.plus, label: "New folder inside…", run: () => root.newFolder(a.id, f.path) }
        ])
    }
    function accountContext(a, item, x, y) {
        const on = a.enabled !== false
        menu.show(item, x, y, MailStore.accountLabel(a), [].concat(
            on ? [{ icon: I.plus, label: "New folder…", run: () => root.newFolder(a.id, "") },
                  { icon: a.collapsed ? I.down : I.right, label: a.collapsed ? "Show folders" : "Hide folders",
                    run: () => MailStore.setAccount(a.id, { collapsed: !a.collapsed }) },
                  { sep: true }] : [],
            [{ icon: I.cog, label: "Account settings…", run: () => root.accountSettings(a.id) },
             { icon: on ? "󰒲" : "󰐥", label: on ? "Turn off" : "Turn on", run: () => MailStore.setAccount(a.id, { enabled: !on }) }]))
    }

    component Label: Text {
        Layout.leftMargin: 4
        Layout.bottomMargin: 2
        color: Colors.fade(0.4)
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.2
        font.family: Properties.fontFamily
    }

    component Entry: Rectangle {
        id: e
        property string v
        property string icon
        property string label
        property int count: 0
        property bool muted: false
        property int indent: 0
        property bool current: false
        property string hint: ""             // e.g. the account of a pinned folder
        property string dot: ""              // a color dot (the account) in front
        property bool pinnable: false
        property bool pinned: false
        property Item glow: null             // the sliding highlight, while current
        onCurrentChanged: if (current && glow) glow.target = e
        Component.onCompleted: if (current && glow) glow.target = e
        signal activated()
        signal pinToggled()
        signal context(real x, real y)        // right-click (where, in the row)
        Layout.fillWidth: true
        implicitHeight: 32
        radius: Properties.radius + 2
        color: "transparent"
        HoverHandler { id: eHover }
        // the row, its pin and the area right of the pin all count as hovering the row
        readonly property bool hovered: eHover.hovered || eMouse.containsMouse || pinHover.containsMouse
        HoverFace { shown: e.hovered && !e.current }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8 + e.indent * 12
            anchors.rightMargin: 8
            spacing: 9
            Text {
                text: e.icon
                color: Icons.tint(e.icon, e.current ? Colors.color6 : Colors.fade(0.55))
                font.pixelSize: 14
                font.family: Properties.fontFamily
                Rectangle {
                    visible: e.dot !== ""
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: -2; bottomMargin: 0 }
                    width: 6; height: 6; radius: 3
                    color: e.dot || "transparent"
                    border.width: 1
                    border.color: Colors.background
                }
            }
            Text {
                Layout.fillWidth: true
                text: e.label + (e.hint ? '<font color="' + Colors.fade(0.4) + '">  ·  ' + e.hint + '</font>' : "")
                textFormat: e.hint ? Text.StyledText : Text.PlainText
                color: e.current ? Colors.ink : Colors.fade(0.78)
                font.pixelSize: 12
                font.bold: e.current || (e.count > 0 && !e.muted)
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            // pin to the favorites / unpin (on hover)
            Text {
                visible: e.pinnable && e.hovered
                text: e.pinned ? "󰤰" : "󰐃"
                color: pinHover.containsMouse ? Colors.color6 : Colors.fade(0.5)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                // a MouseArea (not a TapHandler): the click must not also open the folder
                MouseArea {
                    id: pinHover
                    anchors.fill: parent
                    anchors.margins: -4
                    anchors.rightMargin: -8              // up to the row's edge
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: e.pinToggled()
                }
                ToolTip.visible: pinHover.containsMouse
                ToolTip.text: e.pinned ? "Remove from favorites" : "Pin to favorites"
                ToolTip.delay: 400
            }
            Text {
                visible: e.count > 0 && !(e.pinnable && e.hovered)
                Layout.leftMargin: 4
                text: e.count > 999 ? "999+" : e.count
                color: e.muted ? Colors.fade(0.45) : Colors.color6
                font.pixelSize: 11
                font.bold: !e.muted
                font.family: Properties.fontFamily
            }
        }
        MouseArea {
            id: eMouse
            z: -1                         // under the row's content: the pin takes its own clicks
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.RightButton ? e.context(m.x, m.y) : e.activated()
        }
    }
}
