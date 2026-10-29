import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../calendar"
import "MailIcons.js" as I

// Mail app settings, one page each (list on the left): new mail, reading,
// writing, actions, the sidebar's favorites (the same keys as the settings
// app's Mail page, Settings.mail), then a page per account (name, color,
// signature, notifications, on / off, servers, remove) and export / import.
//   openAccount(id)  — straight to an account's page
PagedModal {
    id: root

    // (first: the account pages' delegates use them)
    component Hint: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        color: Colors.fade(0.42)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
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


    title: "Mail settings"
    icon: I.cog
    signal editAccount(var account)
    signal transfer(string mode)
    signal addAccount()
    property string linkNote: ""
    onShownChanged: if (shown) DefaultApps.refresh()
    function openAccount(id) { openPage("acc:" + id) }
    onActionPicked: id => { if (id === "add") { close(); addAccount() } }

    pages: [
        { id: "new", icon: "󰂚", label: "New mail" },
        { id: "reading", icon: "󰈈", label: "Reading" },
        { id: "writing", icon: "󰏫", label: "Writing" },
        { id: "actions", icon: "󰁨", label: "Actions" },
        { id: "sidebar", icon: "󰕰", label: "Sidebar", heading: "Favorites in the sidebar" }
    ].concat(MailStore.accounts.map((a, i) => ({
        id: "acc:" + a.id, label: MailStore.accountLabel(a), heading: MailStore.accountLabel(a) + "  ·  " + a.email, color: a.color || Colors.color6,
        dim: a.enabled === false, group: i === 0 ? "Accounts" : undefined
    }))).concat([
        { id: "transfer", icon: "󰑓", label: "Export / import", group: MailStore.accounts.length === 0 ? "Accounts" : undefined,
          heading: "Move accounts to another device" },
        { id: "add", icon: "󰐕", label: "Add account", action: true }
    ])

    function opt(key, def) { return Settings.mail[key] ?? def }
    function setOpt(key, v) { Settings.set("mail", key, v) }
    ConfirmArm { id: removeArm }

    // ── New mail ──
    ColumnLayout {
        visible: root.page === "new"
        Layout.fillWidth: true
        spacing: 8
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
        Hint { text: "Notifications per account: on the account's page." }
    }

    // ── Reading ──
    ColumnLayout {
        visible: root.page === "reading"
        Layout.fillWidth: true
        spacing: 8
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
        }
        SectionTitle { text: "Messages" }
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Show messages as"
                desc: "When a message has both"
                ChoiceControl { options: ["html", "text"]; value: root.opt("format", "html"); onEdited: v => root.setOpt("format", v) }
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
                label: "Show image attachments inline"
                desc: "Under the message, like Thunderbird; click one to open the viewer"
                ToggleSwitch { checked: root.opt("inlineAttachments", true); onToggled: v => root.setOpt("inlineAttachments", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Solid background"
                desc: "No transparency behind the mail window"
                ToggleSwitch { checked: root.opt("solid", false); onToggled: v => root.setOpt("solid", v) }
            }
        }
        SectionTitle { text: "Privacy" }
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Load remote content"
                desc: "Images from the web in every message (they can tell the sender you opened it)"
                ToggleSwitch { checked: root.opt("remoteContent", false); onToggled: v => root.setOpt("remoteContent", v) }
            }
            Divider { visible: MailStore.remoteOk.length > 0 }
            PlainRow {
                Layout.fillWidth: true
                visible: MailStore.remoteOk.length > 0
                label: "Senders allowed to load remote content"
                desc: MailStore.remoteOk.join(", ")
                ActionButton { text: "Forget"; onClicked: { MailStore.remoteOk = []; MailStore.saveBook() } }
            }
        }
    }

    // ── Writing ──
    ColumnLayout {
        visible: root.page === "writing"
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Attachment reminder"
                desc: "Asks before sending when you wrote \"attached\" / \"anbei\" but nothing is attached"
                ToggleSwitch { checked: root.opt("attachmentReminder", true); onToggled: v => root.setOpt("attachmentReminder", v) }
            }
        }
        SectionTitle { text: "Signatures"; visible: MailStore.accounts.length > 0 }
        Card {
            visible: MailStore.accounts.length > 0
            Repeater {
                model: MailStore.accounts
                ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Divider { visible: index > 0 }
                    PlainRow {
                        Layout.fillWidth: true
                        label: MailStore.accountLabel(modelData)
                        desc: (modelData.signature ?? "").trim() ? modelData.signature.trim().split("\n")[0] : "No signature"
                        ActionButton { text: "Edit"; onClicked: root.page = "acc:" + modelData.id }
                    }
                }
            }
        }
    }

    // ── Actions ──
    ColumnLayout {
        visible: root.page === "actions"
        Layout.fillWidth: true
        spacing: 8
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
    }

    // ── Sidebar ──
    ColumnLayout {
        visible: root.page === "sidebar"
        Layout.fillWidth: true
        spacing: 8
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
        }
        Hint { text: "Single folders: right-click a folder in the sidebar → Pin to favorites (or the pin on hover)." }
    }

    // ── Export / import ──
    ColumnLayout {
        visible: root.page === "transfer"
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Export"
                desc: "Some or all accounts in one file — with the passwords encrypted by a passphrase, or without them"
                ActionButton { icon: I.open; text: "Export…"; interactive: MailStore.accounts.length > 0; onClicked: { root.close(); root.transfer("export") } }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Import"
                desc: "A file exported here (or from the settings app); an account with the same address is updated"
                ActionButton { icon: I.download; text: "Import…"; onClicked: { root.close(); root.transfer("import") } }
            }
        }
        Hint { text: "Settings → Accounts has the mail and calendar accounts together." }
    }

    // ── one page per account ──
    Repeater {
        model: MailStore.accounts
        ColumnLayout {
            id: accPage
            required property var modelData
            readonly property var a: modelData
            visible: root.page === "acc:" + a.id
            Layout.fillWidth: true
            spacing: 8

            Card {
                PlainRow {
                    Layout.fillWidth: true
                    label: "Checked"
                    desc: accPage.a.enabled !== false ? "New mail is fetched and shown in the sidebar" : "Off — kept, but not checked or shown"
                    ToggleSwitch { checked: accPage.a.enabled !== false; onToggled: v => MailStore.setAccount(accPage.a.id, { enabled: v }) }
                }
                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Notifications"
                    ToggleSwitch { checked: accPage.a.notify !== false; onToggled: v => MailStore.setAccount(accPage.a.id, { notify: v }) }
                }
            }

            SectionTitle { text: "Names" }
            Card {
                PlainRow {
                    Layout.fillWidth: true
                    label: "Name in the sidebar"
                    SearchField {
                        Layout.preferredWidth: 240
                        icon: ""; clearable: false
                        text: accPage.a.name
                        onEditingFinished: if (text.trim() && text !== accPage.a.name) MailStore.setAccount(accPage.a.id, { name: text.trim() })
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
                        text: accPage.a.displayName ?? ""
                        onEditingFinished: if (text !== (accPage.a.displayName ?? "")) MailStore.setAccount(accPage.a.id, { displayName: text.trim() })
                    }
                }
                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Color"
                    desc: "Its dot in the sidebar, the lists and here"
                    Row {
                        spacing: 5
                        Repeater {
                            model: MailStore.palette
                            Rectangle {
                                required property string modelData
                                readonly property bool on: (accPage.a.color ?? "").toLowerCase() === modelData
                                width: 20; height: 20; radius: 10
                                color: modelData
                                border.width: on ? 2 : swatchMouse.containsMouse ? 1.5 : 0
                                border.color: Colors.ink
                                MouseArea {
                                    id: swatchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MailStore.setAccount(accPage.a.id, { color: parent.modelData })
                                }
                            }
                        }
                    }
                }
            }

            SectionTitle { text: "Signature" }
            Card {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 14
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 96
                        radius: 10
                        color: Colors.fade(0.04)
                        border.width: 1
                        border.color: sigArea.activeFocus ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45) : Colors.fade(0.08)
                        TextArea {
                            id: sigArea
                            anchors.fill: parent
                            text: accPage.a.signature ?? ""
                            placeholderText: "Added under new messages and replies"
                            wrapMode: TextEdit.Wrap
                            color: Properties.color
                            placeholderTextColor: Colors.fade(0.35)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                            background: null
                            onActiveFocusChanged: if (!activeFocus && text !== (accPage.a.signature ?? "")) MailStore.setAccount(accPage.a.id, { signature: text })
                        }
                    }
                    Text {
                        text: "Saved when you click elsewhere"
                        color: Colors.fade(0.35)
                        font.pixelSize: 10
                        font.family: Properties.fontFamily
                    }
                }
            }

            SectionTitle { text: "Server" }
            Card {
                PlainRow {
                    Layout.fillWidth: true
                    label: "Servers & password"
                    desc: accPage.a.imap.host + "  ·  " + accPage.a.smtp.host
                    ActionButton { text: "Change…"; onClicked: { root.close(); root.editAccount(accPage.a) } }
                }
                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: removeArm.armed === accPage.a.id ? "Click again to remove" : "Remove this account"
                    desc: "Its password leaves the keyring; the mail stays on the server"
                    ActionButton {
                        icon: I.trash
                        text: removeArm.armed === accPage.a.id ? "Remove" : "Remove…"
                        textColor: removeArm.armed === accPage.a.id ? Colors.red : Colors.ink
                        onClicked: if (removeArm.confirm(accPage.a.id)) MailStore.removeAccount(accPage.a.id)
                    }
                }
            }
        }
    }
}
