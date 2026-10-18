import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// SSH & GPG overview (services/CryptoKeys.qml). Never shows or copies a private key.
ColumnLayout {
    id: page
    spacing: 16

    property string forgetHost: ""
    property string forgetMsg: ""
    property string keyName: "id_ed25519_new"
    property string keyComment: Quickshell.env("USER") + "@" + "archlinux"
    property string newKeyMsg: ""
    property bool showAllGpg: false

    Component.onCompleted: CryptoKeys.refresh()

    // ── SSH ─────────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "SSH keys"
        icon: "󰣀"
        header: ActionButton { icon: "󰑓"; text: "Reload"; onClicked: CryptoKeys.refresh() }
        NetRow {
            first: true
            visible: CryptoKeys.sshKeys.length === 0
            label: CryptoKeys.loading ? "Looking…" : "No keys in ~/.ssh"
        }
        Repeater {
            model: CryptoKeys.sshKeys
            NetRow {
                required property var modelData
                required property int index
                readonly property var k: modelData
                readonly property var warn: [
                    k.passphrase === false ? "no passphrase: anyone who gets the file can use it (ssh-keygen -p -f ~/.ssh/" + k.name + ")" : "",
                    k.hasPrivate && k.mode !== "600" && k.mode !== "400" ? "private key is readable by others (mode " + k.mode + ": chmod 600)" : "",
                    !k.hasPrivate ? "only the public half is here" : ""
                ].filter(x => x)
                first: index === 0
                wide: true
                label: k.name + "  ·  " + k.type + " " + k.bits + (CryptoKeys.agentKeys.includes(k.fingerprint) ? "  ·  in the agent" : "")
                desc: k.fingerprint + "  ·  " + k.comment + (warn.length ? "\n󰀦 " + warn.join("\n󰀦 ") : "")
                RowLayout {
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    ActionButton { icon: "󰆏"; text: "Copy public key"; onClicked: CryptoKeys.copyPublicSsh(k) }
                }
            }
        }
        NetRow {
            label: "Agent"
            desc: CryptoKeys.agentSock === "" ? "no SSH agent for the shell (SSH_AUTH_SOCK isn't set): keys with a passphrase ask every time. e.g. systemctl --user enable --now gcr-ssh-agent.socket, then set SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh in niri's environment"
                : CryptoKeys.agentUp ? CryptoKeys.agentKeys.length + " key(s) loaded" : "SSH_AUTH_SOCK is set but the agent doesn't answer"
        }
        NetRow {
            label: "~/.ssh"
            desc: (CryptoKeys.sshDirMode === "700" ? "permissions ok (700)" : "permissions " + CryptoKeys.sshDirMode + ", should be 700")
                  + "  ·  " + CryptoKeys.knownHosts + " known hosts  ·  " + CryptoKeys.sshHosts.length + " hosts in config" + (CryptoKeys.sshHosts.length ? " (" + CryptoKeys.sshHosts.join(", ") + ")" : "")
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "SSH tools"
        NetRow {
            first: true
            label: "Forget a host key"
            desc: page.forgetMsg !== "" ? page.forgetMsg : "after a server was reinstalled (\"REMOTE HOST IDENTIFICATION HAS CHANGED\"): name, IP or [name]:port"
            RowLayout {
                spacing: 8
                SearchField {
                    Layout.preferredWidth: 220
                    icon: ""; clearable: false
                    placeholderText: "server.example.com"
                    text: page.forgetHost
                    onTextEdited: { page.forgetHost = text; page.forgetMsg = "" }
                }
                ActionButton {
                    text: page.forgetMsg === "click again to remove it" ? "Remove" : "Forget…"
                    textColor: page.forgetMsg === "click again to remove it" ? Colors.red : Colors.ink
                    interactive: page.forgetHost.trim() !== ""
                    onClicked: {
                        if (page.forgetMsg !== "click again to remove it") { page.forgetMsg = "click again to remove it"; return }
                        CryptoKeys.forgetHost(page.forgetHost, (ok, msg) => page.forgetMsg = msg)
                    }
                }
            }
        }
        NetRow {
            label: "New SSH key (ed25519)"
            desc: page.newKeyMsg !== "" ? page.newKeyMsg : "opens a terminal; ssh-keygen asks for the passphrase there"
            RowLayout {
                spacing: 8
                SearchField { Layout.preferredWidth: 150; icon: ""; clearable: false; text: page.keyName; onTextEdited: page.keyName = text }
                SearchField { Layout.preferredWidth: 170; icon: ""; clearable: false; text: page.keyComment; placeholderText: "comment"; onTextEdited: page.keyComment = text }
                ActionButton {
                    icon: "󰐕"; text: "Create"
                    onClicked: { const e = CryptoKeys.newKey(page.keyName.trim(), page.keyComment.trim()); page.newKeyMsg = e || "terminal opened; reload when done" }
                }
            }
        }
    }

    // ── GPG ─────────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "GPG keys"
        icon: "󰌆"
        header: ActionButton {
            visible: CryptoKeys.gpgKeys.some(k => !k.secret)
            text: page.showAllGpg ? "Only mine" : "Show " + CryptoKeys.gpgKeys.filter(k => !k.secret).length + " others"
            onClicked: page.showAllGpg = !page.showAllGpg
        }
        NetRow {
            first: true
            label: CryptoKeys.gpgKeys.filter(k => k.secret).length + " own (secret) keys, " + CryptoKeys.gpgKeys.filter(k => !k.secret).length + " others' keys"
            desc: "git signing: " + (CryptoKeys.gitSigningKey || "no user.signingkey") + (CryptoKeys.gitSign ? " · commits are signed" : " · commit.gpgsign off")
        }
        Repeater {
            model: CryptoKeys.gpgKeys.filter(k => k.secret || page.showAllGpg)
            NetRow {
                required property var modelData
                readonly property var k: modelData
                label: (k.secret ? "󰌆 " : "") + (k.uid || k.keyid)
                desc: k.keyid + (k.revoked ? "  ·  revoked" : k.expired ? "  ·  expired" : k.soon ? "  ·  expires in " + Math.ceil((k.expires - Date.now() / 1000) / 86400) + " days"
                      : k.expires ? "  ·  until " + new Date(k.expires * 1000).toLocaleDateString(Qt.locale(), "yyyy-MM-dd") : "  ·  no expiry")
                ActionButton { icon: "󰆏"; text: "Copy public"; onClicked: CryptoKeys.copyPublicGpg(k.fpr) }
            }
        }
    }
}
