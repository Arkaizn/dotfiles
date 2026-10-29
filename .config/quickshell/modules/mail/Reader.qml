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
    signal reply(var m, bool all)
    signal forward(var m)
    signal closed()
    signal viewAttachment(var m, var atts, int index)

    // the row object changes on every check: follow its messages by id
    readonly property var msgs: (row?.msgs ?? []).map(m => MailStore.byId[m.id] ?? m)
    readonly property var latest: msgs.length ? msgs[msgs.length - 1] : null
    readonly property bool anyUnread: msgs.some(m => !m.seen)
    readonly property bool anyFlagged: msgs.some(m => m.flagged)
    readonly property bool gone: row !== null && msgs.every(m => !MailStore.byId[m.id])

    // another conversation opened: subject and messages come in one after another
    // (like a settings page); the same one refreshed by a check doesn't move
    property string shownKey: ""
    StaggerIn { id: enter; step: 40 }
    onRowChanged: {
        readTimer.stop()
        if (row && anyUnread && MailStore.readDelay !== "never") readTimer.restart()
        const k = row?.key ?? ""
        if (k === shownKey) return
        shownKey = k
        flick.contentY = 0
        if (row) Qt.callLater(() => enter.run([subjectText].concat(Array.from(cards.children).filter(c => c.msg !== undefined))))
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
            Item { width: 13; height: Properties.buttonHeight; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Colors.fade(0.1) } }
            IconButton { icon: I.archive; tooltip: "Archive  (A)"; onClicked: MailStore.moveTo(root.msgs, "archive") }
            IconButton { icon: I.junk; tooltip: "Junk  (J)"; onClicked: MailStore.moveTo(root.msgs, "junk") }
            IconButton { icon: I.trash; tooltip: "Delete  (Del)"; onClicked: MailStore.remove(root.msgs) }
            IconButton {
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
                                    Text { text: I.role(modelData.role); color: Colors.fade(0.55); font.pixelSize: 13; font.family: Properties.fontFamily }
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
            Item { width: 13; height: Properties.buttonHeight; Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Colors.fade(0.1) } }
            IconButton {
                icon: root.anyUnread ? I.mailOpen : I.mail
                tooltip: root.anyUnread ? "Mark as read  (M)" : "Mark as unread  (M)"
                onClicked: { readTimer.stop(); MailStore.markRead(root.msgs, root.anyUnread) }
            }
            IconButton {
                icon: root.anyFlagged ? I.star : I.starOutline
                textColor: root.anyFlagged ? Colors.yellow : Properties.color
                tooltip: root.anyFlagged ? "Remove star  (S)" : "Star  (S)"
                onClicked: MailStore.star(root.anyFlagged ? root.msgs : [root.latest], !root.anyFlagged)
            }
          }
            IconButton { Layout.alignment: Qt.AlignTop; icon: I.close; tooltip: "Close  (Esc)"; onClicked: root.closed() }
        }

        Text {
            id: subjectText
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
                    }
                }
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
