import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../calendar"
import "MailIcons.js" as I

// The mail settings' pages (MailStore.settingsPages lists them), shown one at a
// time: in the mail app's settings dialog (MailSettings, a PagedModal) and as
// sub-pages of Mail in the settings app. Each page: `pageId` + visible: shows(pageId).
//   MailSettingsPages { page: "reading"; onEditAccount: a => …; onTransfer: mode => … }
ColumnLayout {
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

    property string page: ""
    property bool showAll: false            // every page laid out (the dialog's search)
    signal editAccount(var account)
    signal transfer(string mode)
    signal openPage(string id)
    property string linkNote: ""
    function shows(id) { return page === id || showAll }
    function opt(key, def) { return Settings.mail[key] ?? def }
    function setOpt(key, v) { Settings.set("mail", key, v) }
    Component.onCompleted: DefaultApps.refresh()

    spacing: 8
    ConfirmArm { id: removeArm }

    // ── New mail ──
    ColumnLayout {
        readonly property string pageId: "new"
        visible: root.shows(pageId)
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
        readonly property string pageId: "reading"
        visible: root.shows(pageId)
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
                label: "Force dark mode"
                desc: "Like Dark Reader: white backgrounds turn dark, dark text light, the colors' hues stay. Off: the sender's colors on a light page (also the moon in the message toolbar)"
                ToggleSwitch { checked: root.opt("style", "dark") === "dark"; onToggled: v => root.setOpt("style", v ? "dark" : "original") }
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
        readonly property string pageId: "writing"
        visible: root.shows(pageId)
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
                        ActionButton { text: "Edit"; onClicked: root.openPage("acc:" + modelData.id) }
                    }
                }
            }
        }
    }

    // ── Actions ──
    ColumnLayout {
        readonly property string pageId: "actions"
        visible: root.shows(pageId)
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
        readonly property string pageId: "sidebar"
        visible: root.shows(pageId)
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
        readonly property string pageId: "transfer"
        visible: root.shows(pageId)
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Export"
                desc: "Some or all accounts in one file — with the passwords encrypted by a passphrase, or without them"
                ActionButton { icon: I.open; text: "Export…"; interactive: MailStore.accounts.length > 0; onClicked: root.transfer("export") }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Import"
                desc: "A file exported here (or from the settings app); an account with the same address is updated"
                ActionButton { icon: I.download; text: "Import…"; onClicked: root.transfer("import") }
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
            readonly property string pageId: "acc:" + a.id
            visible: root.shows(pageId)
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
                    ActionButton { text: "Change…"; onClicked: root.editAccount(accPage.a) }
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
