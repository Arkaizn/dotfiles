import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../calendar"
import "MailIcons.js" as I

// Mail app settings: the general options (the same keys as the settings app's
// Mail page, Settings.mail) and per account: name, signature, notifications,
// on / off, servers, remove.
Modal {
    id: root

    cardWidth: 660
    signal editAccount(var account)
    signal transfer(string mode)
    property string linkNote: ""
    onShownChanged: if (shown) DefaultApps.refresh()

    function opt(key, def) { return Settings.mail[key] ?? def }
    function setOpt(key, v) { Settings.set("mail", key, v) }
    ConfirmArm { id: removeArm }

    ColumnLayout {
        width: parent.width
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: I.cog; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: "Mail settings"; color: Colors.ink; font.pixelSize: 17; font.bold: true; font.family: Properties.fontFamily }
                Text { text: "Changes apply right away"; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: I.close; onClicked: root.close() }
        }

        Flickable {
            id: settingsFlick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(body.implicitHeight, root.height - 160)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: CalScrollBar {}
            SmoothWheel { flick: settingsFlick; step: 140 }     // like the settings app

            ColumnLayout {
                id: body
                width: parent.width - 8
                spacing: 8

                SectionTitle { text: "New mail" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Check every"
                        desc: "Minutes, also with the app closed"
                        ChoiceControl { options: ["2", "5", "10", "15", "30"]; value: root.opt("checkMinutes", "5"); onEdited: v => root.setOpt("checkMinutes", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Notifications"
                        desc: "One per new message (grouped when many come at once)"
                        ToggleSwitch { checked: root.opt("notify", true); onToggled: v => root.setOpt("notify", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        enabled: root.opt("notify", true)
                        opacity: enabled ? 1 : 0.4
                        label: "Sound"
                        desc: "Not with do not disturb on"
                        RowLayout {
                            spacing: 4
                            IconButton { implicitWidth: 26; implicitHeight: 26; iconSize: 11; icon: "󰐊"; tooltip: "Play it"
                                         visible: root.opt("sound", "message") !== "off"; onClicked: MailStore.playSound(root.opt("sound", "message")) }
                            ChoiceControl { options: ["off", "message", "bell", "complete"]; value: root.opt("sound", "message")
                                            onEdited: v => { root.setOpt("sound", v); MailStore.playSound(v) } }
                        }
                    }
                }

                SectionTitle { text: "Reading" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Mark as read"
                        desc: "Seconds after opening a message"
                        ChoiceControl { options: ["0", "2", "5", "never"]; value: root.opt("markRead", "2"); onEdited: v => root.setOpt("markRead", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Conversations"
                        desc: "Group replies with the message they answer"
                        ToggleSwitch { checked: root.opt("threads", true); onToggled: v => root.setOpt("threads", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Show messages as"
                        desc: "When a message has both"
                        ChoiceControl { options: ["html", "text"]; value: root.opt("format", "html"); onEdited: v => root.setOpt("format", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Load remote content"
                        desc: "Images from the web in every message (they can tell the sender you opened it)"
                        ToggleSwitch { checked: root.opt("remoteContent", false); onToggled: v => root.setOpt("remoteContent", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Message style"
                        desc: "original: the sender's colors on a light page · dark: the theme's colors (like Thunderbird's dark mode)"
                        ChoiceControl { options: ["original", "dark"]; value: root.opt("style", "original"); onEdited: v => root.setOpt("style", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Solid background"
                        desc: "No transparency behind the mail window"
                        ToggleSwitch { checked: root.opt("solid", false); onToggled: v => root.setOpt("solid", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Show image attachments inline"
                        desc: "Under the message, like Thunderbird; click one to open the viewer"
                        ToggleSwitch { checked: root.opt("inlineAttachments", true); onToggled: v => root.setOpt("inlineAttachments", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        visible: MailStore.remoteOk.length > 0
                        label: "Senders allowed to load remote content"
                        desc: MailStore.remoteOk.join(", ")
                        ActionButton { text: "Forget"; onClicked: { MailStore.remoteOk = []; MailStore.saveBook() } }
                    }
                }

                SectionTitle { text: "Writing & actions" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Undo archive / delete for"
                        desc: "Seconds; the server only gets the change after that (Ctrl+Z)"
                        ChoiceControl { options: ["0", "5", "10", "20"]; value: root.opt("undo", "5"); onEdited: v => root.setOpt("undo", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Attachment reminder"
                        desc: "Asks before sending when you wrote \"attached\" / \"anbei\" but nothing is attached"
                        ToggleSwitch { checked: root.opt("attachmentReminder", true); onToggled: v => root.setOpt("attachmentReminder", v) }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Email links"
                        desc: root.linkNote || (MailStore.isMailtoHandler ? "mailto: links open here" : "mailto: links open in " + (DefaultApps.name(DefaultApps.current["mail"] ?? "") || "another app"))
                        ActionButton {
                            visible: !MailStore.isMailtoHandler
                            icon: I.mail
                            text: "Open them here"
                            onClicked: MailStore.useForMailto((ok, err) => root.linkNote = ok ? "" : err)
                        }
                    }
                }

                SectionTitle { text: "Move accounts to another device" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Export / import"
                        desc: "All accounts in one file — with the passwords encrypted by a passphrase, or without them"
                        RowLayout {
                            spacing: 6
                            ActionButton { icon: I.open; text: "Export…"; interactive: MailStore.accounts.length > 0; onClicked: { root.close(); root.transfer("export") } }
                            ActionButton { icon: I.download; text: "Import…"; onClicked: { root.close(); root.transfer("import") } }
                        }
                    }
                }

                SectionTitle { text: "Favorites in the sidebar" }
                Card {
                    Repeater {
                        model: [["inbox", "All inboxes", ""], ["unread", "Unread", "Unread messages of all inboxes"],
                                ["flagged", "Starred", "Starred messages anywhere"], ["sent", "All sent", "Every account's sent folder together"],
                                ["drafts", "All drafts", ""], ["archive", "All archived", ""], ["trash", "All deleted", "Every account's trash"],
                                ["junk", "All junk", ""]]
                        ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0
                            Divider { visible: index > 0 }
                            PlainRow {
                                Layout.fillWidth: true
                                label: modelData[1]
                                desc: modelData[2]
                                ToggleSwitch {
                                    checked: MailStore.favorites.includes(modelData[0])
                                    onToggled: v => root.setOpt(MailStore.favKeys[modelData[0]], v)
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 14
                        text: "Single folders: the pin next to a folder in the sidebar."
                        color: Colors.fade(0.45)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        wrapMode: Text.Wrap
                    }
                }

                // ── accounts ──
                SectionTitle { text: "Accounts" }
                Text {
                    Layout.leftMargin: 6
                    visible: MailStore.accounts.length === 0
                    text: "No accounts yet — add one with ＋ in the sidebar."
                    color: Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                Repeater {
                    model: MailStore.accounts
                    Card {
                        id: accCard
                        required property var modelData
                        readonly property var a: modelData
                        PlainRow {
                            Layout.fillWidth: true
                            label: accCard.a.email
                            desc: accCard.a.imap.host + "  ·  " + accCard.a.smtp.host
                            RowLayout {
                                spacing: 4
                                ActionButton { text: "Servers & password"; onClicked: { root.close(); root.editAccount(accCard.a) } }
                                ToggleSwitch { checked: accCard.a.enabled !== false; onToggled: v => MailStore.setAccount(accCard.a.id, { enabled: v }) }
                            }
                        }
                        Divider {}
                        PlainRow {
                            Layout.fillWidth: true
                            label: "Name in the sidebar"
                            SearchField {
                                Layout.preferredWidth: 240
                                icon: ""; clearable: false
                                text: accCard.a.name
                                onEditingFinished: if (text.trim() && text !== accCard.a.name) MailStore.setAccount(accCard.a.id, { name: text.trim() })
                            }
                        }
                        Divider {}
                        PlainRow {
                            Layout.fillWidth: true
                            label: "Your name"
                            desc: "What people see as the sender"
                            SearchField {
                                Layout.preferredWidth: 240
                                icon: ""; clearable: false
                                text: accCard.a.displayName ?? ""
                                onEditingFinished: if (text !== (accCard.a.displayName ?? "")) MailStore.setAccount(accCard.a.id, { displayName: text.trim() })
                            }
                        }
                        Divider {}
                        PlainRow {
                            Layout.fillWidth: true
                            label: "Notifications"
                            ToggleSwitch { checked: accCard.a.notify !== false; onToggled: v => MailStore.setAccount(accCard.a.id, { notify: v }) }
                        }
                        Divider {}
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6
                            Text { text: "Signature"; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 84
                                radius: 10
                                color: Colors.fade(0.04)
                                border.width: 1
                                border.color: Colors.fade(0.08)
                                TextArea {
                                    anchors.fill: parent
                                    text: accCard.a.signature ?? ""
                                    placeholderText: "Added under new messages and replies"
                                    wrapMode: TextEdit.Wrap
                                    color: Properties.color
                                    placeholderTextColor: Colors.fade(0.35)
                                    font.pixelSize: 12
                                    font.family: Properties.fontFamily
                                    background: null
                                    onActiveFocusChanged: if (!activeFocus && text !== (accCard.a.signature ?? "")) MailStore.setAccount(accCard.a.id, { signature: text })
                                }
                            }
                        }
                        Divider {}
                        PlainRow {
                            Layout.fillWidth: true
                            label: removeArm.armed === accCard.a.id ? "Click again to remove" : "Remove this account"
                            desc: "Its password leaves the keyring; the mail stays on the server"
                            ActionButton {
                                icon: I.trash
                                text: removeArm.armed === accCard.a.id ? "Remove" : "Remove…"
                                textColor: removeArm.armed === accCard.a.id ? Colors.red : Colors.ink
                                onClicked: if (removeArm.confirm(accCard.a.id)) MailStore.removeAccount(accCard.a.id)
                            }
                        }
                    }
                }
            }
        }
    }

    component SectionTitle: Text {
        Layout.leftMargin: 6
        Layout.topMargin: 6
        color: Colors.fade(0.55)
        font.pixelSize: 12
        font.bold: true
        font.family: Properties.fontFamily
    }
    component Card: Rectangle {
        default property alias content: col.data
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight
        radius: 14
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        ColumnLayout { id: col; width: parent.width; spacing: 0 }
    }
    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        implicitHeight: 1
        color: Colors.fade(0.06)
    }
}
