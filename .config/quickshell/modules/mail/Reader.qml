import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../calendar"
import "../settings"
import "MailIcons.js" as I

// The right column: the open conversation (newest and unread messages
// unfolded), with the actions for it on top. Marked as read after a moment
// (settings: Mail → mark as read).
Rectangle {
    id: root

    property var row: null                   // { key, msgs, … } from MessageList
    property var order: []                   // the list's row keys, top to bottom (which way a message comes in)
    signal reply(var m, bool all)
    signal forward(var m)
    signal closed()
    signal viewAttachment(var m, var atts, int index)

    // the row object changes on every check: follow its messages by id
    readonly property var msgs: (row?.msgs ?? []).map(m => MailStore.byId[m.id] ?? m)
    readonly property var latest: msgs.length ? msgs[msgs.length - 1] : null
    readonly property bool anyUnread: msgs.some(m => !m.seen)
    readonly property bool anyFlagged: msgs.some(m => m.flagged)
    readonly property bool gone: row !== null && !row.file && msgs.every(m => !MailStore.byId[m.id])
    readonly property bool isFile: !!row?.file          // an .eml opened from disk: in no folder
    // the link under the pointer in one of the messages (MessageCard.linkHover), for the bar at the bottom
    property var hoverLink: null

    // another conversation opened: it comes in from where it is in the list (one
    // further down from below, further up from above; the first one rises a little),
    // like the mail settings' pages; the same one refreshed by a check doesn't move
    property string shownKey: ""
    onRowChanged: {
        readTimer.stop()
        hoverLink = null
        if (row && anyUnread && MailStore.readDelay !== "never") readTimer.restart()
        const k = row?.key ?? ""
        if (k === shownKey) return
        const from = order.indexOf(shownKey), to = order.indexOf(k)
        enter.dir = from < 0 || to < 0 ? 0.5 : to > from ? 1 : -1
        shownKey = k
        flick.contentY = 0
        if (row) enter.restart()
    }
    ParallelAnimation {
        id: enter
        property real dir: 0             // 1: from below, -1: from above
        NumberAnimation { target: subjectText; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: subjectShift; property: "y"; from: enter.dir * 26; to: 0; duration: 380; easing.type: Easing.OutQuint }
        SequentialAnimation {
            PropertyAction { target: cards; property: "opacity"; value: 0 }
            PropertyAction { target: cardsShift; property: "y"; value: enter.dir * 26 }
            PauseAnimation { duration: 40 }
            ParallelAnimation {
                NumberAnimation { target: cards; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                NumberAnimation { target: cardsShift; property: "y"; to: 0; duration: 380; easing.type: Easing.OutQuint }
            }
        }
    }
    Timer {
        id: readTimer
        interval: Math.max(1, parseInt(MailStore.readDelay) || 0) * 1000
        onTriggered: MailStore.markRead(root.msgs, true)
    }

    radius: 12
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        visible: root.row !== null && !root.gone

        // toolbar (thin lines between the groups): the buttons wrap onto a second row when the reader is narrow
        // (one row would force the reader wider than it is: everything cut off)
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
          Flow {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2
            IconButton { icon: I.reply; tooltip: "Reply  (R)"; onClicked: root.reply(root.latest, false) }
            IconButton { icon: I.replyAll; tooltip: "Reply all  (Shift+R)"; onClicked: root.reply(root.latest, true) }
            IconButton { icon: I.forward; tooltip: "Forward  (F)"; onClicked: root.forward(root.latest) }
            Item { visible: !root.isFile; width: 13; height: Properties.buttonHeight; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Colors.fade(0.1) } }
            // (an opened .eml file is in no folder: nothing to archive, move or mark)
            IconButton { visible: !root.isFile; icon: I.archive; tooltip: "Archive  (A)"; onClicked: MailStore.moveTo(root.msgs, "archive") }
            IconButton { visible: !root.isFile; icon: I.junk; tooltip: "Junk  (J)"; onClicked: MailStore.moveTo(root.msgs, "junk") }
            IconButton { visible: !root.isFile; icon: I.trash; tooltip: "Delete  (Del)"; onClicked: MailStore.remove(root.msgs) }
            IconButton {
                visible: !root.isFile
                icon: I.folder; tooltip: "Move to…"
                onClicked: moveMenu.open()
                Popup {
                    id: moveMenu
                    // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
                    scale: AppZoom.at(parent)
                    transformOrigin: Popup.TopLeft
                    y: parent.height + 4
                    padding: 6
                    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                    background: Rectangle {
                        radius: Properties.popupRadius
                        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.panelBorder
                    }
                    contentItem: Column {
                        spacing: 1
                        Repeater {
                            model: (MailStore.accountMap[root.latest?.account]?.folders ?? []).filter(f => f.path !== root.latest?.folder)
                            Rectangle {
                                required property var modelData
                                width: Math.max(200, fRow.implicitWidth + 20)
                                height: 28
                                radius: 7
                                color: fMouse.containsMouse ? Colors.fade(0.08) : "transparent"
                                Row {
                                    id: fRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    spacing: 8
                                    Text { text: I.role(modelData.role); color: Icons.tint(text, Colors.fade(0.55)); font.pixelSize: 13; font.family: Properties.fontFamily }
                                    Text { text: modelData.role === "inbox" ? "Inbox" : modelData.path; color: Colors.fade(0.85)
                                           font.pixelSize: 12; font.family: Properties.fontFamily }
                                }
                                MouseArea {
                                    id: fMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { moveMenu.close(); MailStore.moveTo(root.msgs, modelData.path) }
                                }
                            }
                        }
                    }
                }
            }
            Item { visible: !root.isFile; width: 13; height: Properties.buttonHeight; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Colors.fade(0.1) } }
            IconButton {
                visible: !root.isFile
                icon: root.anyUnread ? I.mailOpen : I.mail
                tooltip: root.anyUnread ? "Mark as read  (M)" : "Mark as unread  (M)"
                onClicked: { readTimer.stop(); MailStore.markRead(root.msgs, root.anyUnread) }
            }
            IconButton {
                visible: !root.isFile
                icon: root.anyFlagged ? I.star : I.starOutline
                tooltip: root.anyFlagged ? "Remove star  (S)" : "Star  (S)"
                onClicked: MailStore.star(root.anyFlagged ? root.msgs : [root.latest], !root.anyFlagged)
            }
            Item { width: 13; height: Properties.buttonHeight; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Colors.fade(0.1) } }
            IconButton {
                icon: MailStore.style === "dark" ? I.moon : I.sun
                tooltip: MailStore.style === "dark" ? "Dark mode on — show the sender's colors" : "Force dark mode"
                onClicked: Settings.set("mail", "style", MailStore.style === "dark" ? "original" : "dark")
            }
          }
            IconButton { Layout.alignment: Qt.AlignTop; icon: I.close; tooltip: "Close  (Esc)"; onClicked: root.closed() }
        }

        // an .eml opened from disk: which file
        Text {
            visible: root.isFile
            Layout.fillWidth: true
            text: "󰈙  " + (root.row?.file ?? "").split("/").pop() + "  ·  opened from a file, not in your mailbox"
            color: Colors.fade(0.45)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Text {
            id: subjectText
            transform: Translate { id: subjectShift }
            Layout.fillWidth: true
            text: root.row?.subject || root.latest?.subject || "(no subject)"
            color: Colors.ink
            font.pixelSize: 19
            font.bold: true
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: CalScrollBar {}
            SmoothWheel { flick: flick; step: 140 }

            ColumnLayout {
                id: cards
                transform: Translate { id: cardsShift }
                width: flick.width - 10
                spacing: 8
                Repeater {
                    model: root.row ? root.row.msgs : []
                    MessageCard {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        msg: MailStore.byId[modelData.id] ?? modelData
                        expanded: index === (root.row?.msgs.length ?? 0) - 1 || !modelData.seen
                        onReply: (m, all) => root.reply(m, all)
                        onForward: m => root.forward(m)
                        onViewAttachment: (m, atts, i) => root.viewAttachment(m, atts, i)
                        onLinkHover: info => root.hoverLink = info
                    }
                }
            }
        }
    }

    // ── the link under the pointer: where it goes (like a browser's status bar) ──
    // the site in bold; red with the reason when the link looks like a trick
    // (MailUtil.linkCheck): such a link needs a second click to open
    Rectangle {
        id: linkBar
        property var info: null                  // kept while fading out
        readonly property bool warn: (info?.warn ?? "") !== ""
        Connections { target: root; function onHoverLinkChanged() { if (root.hoverLink) linkBar.info = root.hoverLink } }
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 10
        width: Math.min(parent.width - 20, linkCol.implicitWidth + 24)
        height: linkCol.implicitHeight + 14
        radius: 10
        z: 20
        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
        // red tint over the solid background (see-through it was unreadable over the message)
        Rectangle { anchors.fill: parent; radius: parent.radius; visible: linkBar.warn; color: Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.14) }
        border.width: 1
        border.color: warn ? Colors.red : Properties.cardBorder
        opacity: root.hoverLink ? 1 : 0
        visible: opacity > 0
        transform: Translate { y: root.hoverLink ? 0 : 6; Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
        // escaped, the site bold, very long ones cut in the middle
        function styled(i) {
            if (!i) return ""
            const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            const dim = c => '<font color="' + c + '">'
            let u = i.url
            if (u.length > 160) u = u.slice(0, 110) + "…" + u.slice(-40)
            if (i.scheme === "qsdate") return dim(Colors.fade(0.6)) + "Add to calendar  ·  </font><b>" + esc(i.label) + "</b>"
            if (i.scheme === "mailto") return dim(Colors.fade(0.5)) + "Email to </font><b>" + esc(decodeURIComponent(u.slice(7).split("?")[0])) + "</b>"
            const hi = i.host ? u.toLowerCase().indexOf(i.host) : -1
            if (hi < 0) return esc(u)
            const siteAt = hi + i.host.length - i.site.length
            return dim(Colors.fade(0.45)) + esc(u.slice(0, hi)) + "</font>" + dim(Colors.fade(0.7)) + esc(u.slice(hi, siteAt)) + "</font>"
                 + "<b>" + esc(u.slice(siteAt, hi + i.host.length)) + "</b>" + dim(Colors.fade(0.45)) + esc(u.slice(hi + i.host.length)) + "</font>"
        }
        ColumnLayout {
            id: linkCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 3
            RowLayout {
                spacing: 8
                Layout.maximumWidth: linkBar.parent.width - 44
                Text {
                    text: linkBar.warn ? "󰀦" : linkBar.info?.scheme === "mailto" ? I.mail : linkBar.info?.scheme === "qsdate" ? "󰃭" : "󰌹"
                    color: linkBar.warn ? Colors.red : linkBar.info?.scheme === "qsdate" ? Colors.color6 : Colors.fade(0.55)
                    font.pixelSize: 13
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: linkBar.styled(linkBar.info)
                    textFormat: Text.StyledText
                    color: Colors.ink
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            Text {
                visible: linkBar.warn
                Layout.maximumWidth: linkBar.parent.width - 44
                text: (linkBar.info?.warn ?? "") + (linkBar.info?.armed ? "  ·  click again to open it anyway" : "  ·  it takes two clicks to open")
                color: Colors.red
                font.pixelSize: 11
                font.bold: true
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
        }
    }

    // nothing open
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 80
        visible: root.row === null || root.gone
        spacing: 8
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: I.mail
            color: Colors.fade(0.15)
            font.pixelSize: 54
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: MailStore.unread > 0 ? MailStore.unread + (MailStore.unread === 1 ? " unread message" : " unread messages") : "All read"
            color: Colors.fade(0.5)
            font.pixelSize: 14
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "↑ ↓ to move  ·  R reply  ·  A archive  ·  N next unread  ·  Ctrl+N new"
            color: Colors.fade(0.3)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
    }
}
