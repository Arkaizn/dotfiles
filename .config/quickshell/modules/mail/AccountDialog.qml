import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../calendar"
import "../settings/network"
import "MailIcons.js" as I

// Add (or edit) a mail account. Typing the address finds the servers by itself
// (built-in presets, then Thunderbird's list, then the provider's own file, then a
// guess); the login is tested (receiving and sending) before anything is saved.
//   start()  edit(account)
Modal {
    id: root

    cardWidth: 560

    property var editing: null
    property string fName: ""
    property string fEmail: ""
    property string fPass: ""
    property string fUser: ""
    property string imapHost: ""
    property string imapPort: "993"
    property string imapSec: "ssl"
    property string smtpHost: ""
    property string smtpPort: "465"
    property string smtpSec: "ssl"
    property string provider: ""
    property string hint: ""
    property string hintUrl: ""
    property string source: ""
    property bool looking: false
    property bool advanced: false
    property bool testing: false
    property string error: ""
    property string lookedUp: ""

    function start() {
        editing = null
        fName = ""; fEmail = ""; fPass = ""; fUser = ""
        imapHost = ""; imapPort = "993"; imapSec = "ssl"; smtpHost = ""; smtpPort = "465"; smtpSec = "ssl"
        provider = ""; hint = ""; hintUrl = ""; source = ""; advanced = false; error = ""; lookedUp = ""
        open()
        Qt.callLater(() => nameField.forceActiveFocus())
    }

    function edit(a) {
        start()
        editing = a
        fName = a.displayName ?? ""; fEmail = a.email; fUser = a.username
        imapHost = a.imap.host; imapPort = String(a.imap.port); imapSec = a.imap.security
        smtpHost = a.smtp.host; smtpPort = String(a.smtp.port); smtpSec = a.smtp.security
        provider = a.provider ?? ""; lookedUp = a.email; source = "saved"
        advanced = true
    }

    readonly property string sourceText: source === "saved" ? "saved settings" : source === "guessed" ? "guessed"
                                       : source === "built in" ? "known provider" : "from " + source
    readonly property bool emailOk: /^[^@\s]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(fEmail.trim())

    // look the servers up a moment after typing stops
    Timer { id: lookTimer; interval: 700; onTriggered: root.lookup() }
    onFEmailChanged: if (shown && !editing) lookTimer.restart()
    function lookup() {
        const e = fEmail.trim()
        if (!emailOk || e === lookedUp) return
        looking = true
        MailStore.autoconfig(e, res => {
            looking = false
            if (fEmail.trim() !== e) return
            lookedUp = e
            if (!res.ok) { error = res.error; hint = ""; source = ""; return }
            error = ""
            imapHost = res.imap.host; imapPort = String(res.imap.port); imapSec = res.imap.security
            smtpHost = res.smtp.host; smtpPort = String(res.smtp.port); smtpSec = res.smtp.security
            fUser = res.username; provider = res.provider; hint = res.hint; hintUrl = res.url; source = res.source
            if (res.source === "guessed") advanced = true
        })
    }

    function account() {
        const e = fEmail.trim()
        return {
            id: editing ? editing.id : MailStore.newAccountId(),
            name: editing?.name || e, email: e, displayName: fName.trim(), username: fUser.trim() || e, provider: provider,
            imap: { host: imapHost.trim(), port: parseInt(imapPort) || 993, security: imapSec },
            smtp: { host: smtpHost.trim(), port: parseInt(smtpPort) || 465, security: smtpSec }
        }
    }

    function save() {
        if (!emailOk) { error = "Enter your email address"; return }
        if (!editing && !fPass) { error = "Enter the password (most providers want an app password)"; return }
        if (!imapHost.trim() || !smtpHost.trim()) { error = "The server names are missing"; advanced = true; return }
        const acc = account()
        testing = true
        error = ""
        MailStore.testAccount(acc, fPass, res => {
            if (!res.ok) { testing = false; error = res.error; return }
            MailStore.addAccount(acc, fPass, res.folders, r => {
                testing = false
                if (!r.ok) { error = r.error; return }
                fPass = ""
                close()
            })
        })
    }

    ColumnLayout {
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: I.mail; color: Colors.color6; font.pixelSize: 22; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.editing ? "Edit " + root.editing.email : "Add a mail account"
                    color: Colors.ink
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "iCloud, Gmail, Yahoo, Fastmail, GMX, mailbox.org, Posteo, any IMAP server"
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: I.close; onClicked: root.close() }
        }

        SearchField {
            id: nameField
            Layout.fillWidth: true
            icon: ""; clearable: false
            placeholderText: "Your name (shown to the people you write to)"
            text: root.fName
            onTextEdited: root.fName = text
            KeyNavigation.tab: emailField
        }
        SearchField {
            id: emailField
            Layout.fillWidth: true
            icon: I.mail; clearable: false
            placeholderText: "Email address"
            enabled: !root.editing
            text: root.fEmail
            onTextEdited: root.fEmail = text
            onEditingFinished: root.lookup()
            KeyNavigation.tab: passField
        }
        SearchField {
            id: passField
            Layout.fillWidth: true
            icon: "󰌋"
            password: true
            placeholderText: root.editing ? "Password (empty = keep the stored one)" : "Password or app password"
            text: root.fPass
            onTextEdited: root.fPass = text
            onAccepted: root.save()
        }

        // what was found + how to get the app password
        Reveal {
          open: root.looking || root.source !== ""
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: found.implicitHeight + 20
            Behavior on implicitHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            radius: 10
            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08)
            ColumnLayout {
                id: found
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: root.looking ? "Looking up the servers…"
                        : "󰄬  " + root.imapHost + " / " + root.smtpHost + "  ·  " + root.sourceText
                    color: Colors.fade(0.7)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.hint !== ""
                    text: root.hint
                    color: Colors.fade(0.85)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    wrapMode: Text.Wrap
                }
                ActionButton {
                    visible: root.hintUrl !== ""
                    icon: I.open
                    text: root.provider === "proton" ? "Get Proton Mail Bridge" : "Make an app password"
                    onClicked: Qt.openUrlExternally(root.hintUrl)
                }
            }
          }
        }

        // servers
        Text {
            text: '<a href="x">' + (root.advanced ? "Hide server settings" : "Server settings") + '</a>'
            textFormat: Text.StyledText
            linkColor: Colors.fade(0.55)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            onLinkActivated: root.advanced = !root.advanced
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        Reveal {
          open: root.advanced
          spacing: 8
          GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 8
            rowSpacing: 8
            Text { text: "Receive (IMAP)"; color: Colors.fade(0.6); font.pixelSize: 11; font.family: Properties.fontFamily }
            SearchField { Layout.fillWidth: true; icon: ""; clearable: false; placeholderText: "imap.example.org"
                          text: root.imapHost; onTextEdited: root.imapHost = text }
            SearchField { Layout.preferredWidth: 70; icon: ""; clearable: false; text: root.imapPort; onTextEdited: root.imapPort = text }
            Segmented { small: true; value: root.imapSec; onEdited: v => root.imapSec = v
                        options: [{ label: "SSL", value: "ssl" }, { label: "STARTTLS", value: "starttls" }, { label: "None", value: "none" }] }
            Text { text: "Send (SMTP)"; color: Colors.fade(0.6); font.pixelSize: 11; font.family: Properties.fontFamily }
            SearchField { Layout.fillWidth: true; icon: ""; clearable: false; placeholderText: "smtp.example.org"
                          text: root.smtpHost; onTextEdited: root.smtpHost = text }
            SearchField { Layout.preferredWidth: 70; icon: ""; clearable: false; text: root.smtpPort; onTextEdited: root.smtpPort = text }
            Segmented { small: true; value: root.smtpSec; onEdited: v => root.smtpSec = v
                        options: [{ label: "SSL", value: "ssl" }, { label: "STARTTLS", value: "starttls" }, { label: "None", value: "none" }] }
            Text { text: "User name"; color: Colors.fade(0.6); font.pixelSize: 11; font.family: Properties.fontFamily }
            SearchField { Layout.fillWidth: true; Layout.columnSpan: 3; icon: ""; clearable: false; placeholderText: "usually the address"
                          text: root.fUser; onTextEdited: root.fUser = text }
        }
          Text {
            Layout.fillWidth: true
            text: "\"None\" (no encryption) only works for servers on this computer, like Proton Mail Bridge."
            color: Colors.fade(0.4)
            font.pixelSize: 10
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
          }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.error || (root.testing ? "Checking the login (receiving and sending)…" : "󰌾  The password goes to your keyring, nowhere else.")
                color: root.error ? Colors.red : Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
            ActionButton { text: "Cancel"; onClicked: root.close() }
            ActionButton {
                icon: "󰄬"
                text: root.testing ? "Checking…" : root.editing ? "Save" : "Add account"
                primary: true
                interactive: !root.testing && !root.looking
                onClicked: root.save()
            }
        }
    }
}
