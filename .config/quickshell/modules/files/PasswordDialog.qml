import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons

// What a mount, a server or an archive asks (FmOps.question, kind password /
// question): a LUKS passphrase, a server's user / domain / password (anonymous
// where it may; "Remember" lets GVfs keep it in the keyring), an archive's
// password, or one of a few choices ("still in use: unmount anyway?").
// The password goes back over the backend's stdin only — never into a file,
// a command line or a log.
//   PasswordDialog { ops; mine }
Modal {
    id: root

    required property var ops
    property bool mine: true
    readonly property var q: mine && ops.question && ["password", "question"].includes(ops.question.kind) ? ops.question : null
    cardWidth: 460
    keepOpen: true

    onQChanged: {
        if (q) {
            user.text = q.user ?? ""
            domain.text = q.domain ?? ""
            pass.text = ""
            remember.checked = false
            anonymous.checked = false
            open()
            Qt.callLater(() => (q.needUser && user.text === "" ? user : pass).forceActiveFocus())
        } else {
            pass.text = ""
            close()
        }
    }
    function send() {
        if (!q) return
        const a = { password: pass.text, anonymous: anonymous.checked, remember: remember.checked }
        if (q.needUser) a.user = user.text
        if (q.needDomain) a.domain = domain.text
        pass.text = ""
        ops.answer("ok", false, "", a)
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: FmIcons.g.lock; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text {
                    Layout.fillWidth: true
                    text: root.q?.kind === "question" ? "A question" : "Password needed"
                    color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.q?.label ?? ""
                    color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.q?.message ?? ""
            color: Colors.fade(0.85); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
            wrapMode: Text.Wrap; textFormat: Text.PlainText
        }

        // a password (and maybe user / domain)
        ColumnLayout {
            visible: root.q?.kind === "password"
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Checkbox {
                id: anonymous
                visible: root.q?.anonymous === true
                Layout.fillWidth: true
                label: "Connect anonymously"
                onClicked: checked = !checked
            }
            SearchField { id: user; visible: root.q?.needUser === true && !anonymous.checked; Layout.fillWidth: true; icon: "󰀄"; placeholderText: "User" }
            SearchField { id: domain; visible: root.q?.needDomain === true && !anonymous.checked; Layout.fillWidth: true; icon: "󰒍"; placeholderText: "Domain / workgroup" }
            SearchField {
                id: pass
                visible: root.q?.needPassword !== false && !anonymous.checked
                Layout.fillWidth: true
                password: true
                icon: FmIcons.g.key
                placeholderText: "Password"
                onAccepted: root.send()
            }
            Checkbox {
                id: remember
                visible: root.q?.canSave === true && !anonymous.checked
                Layout.fillWidth: true
                label: "Remember it (in your keyring)"
                onClicked: checked = !checked
            }
        }

        // choices
        Flow {
            visible: root.q?.kind === "question"
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Repeater {
                model: root.q?.kind === "question" ? root.q.choices : []
                ActionButton {
                    required property string modelData
                    required property int index
                    text: modelData
                    onClicked: root.ops.answer("ok", false, "", { choice: index })
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.ops.answer("cancel") }
            ActionButton {
                visible: root.q?.kind === "password"
                text: "Unlock"
                variant: "primary"
                onClicked: root.send()
            }
        }
    }
}
