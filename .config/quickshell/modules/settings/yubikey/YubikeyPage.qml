import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// YubiKey login: what the dotfiles' setup script (scripts/postinstall/yubikey.sh)
// reports with --status --json (services/Yubikey.qml), so the page and the script
// can't disagree. Changes only happen in the script, in a terminal: it backs up
// system-auth first and tests with sudo -k. Never shows a secret (the script's status
// has no OTP API key or key handle in it).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var s: Yubikey.status
    Component.onCompleted: Yubikey.loadStatus()

    readonly property string modeText: !s ? "" : ({
        none: "Password only: the YubiKey isn't used for logging in",
        fido2: "FIDO2 (pam_u2f, offline): touch the key. Lockscreen: just touch it; sudo, TTY and the login screen: Enter on the empty prompt, then touch",
        otp: "OTP (pam_yubico, YubiCloud): the key types a code into the password field; needs internet",
        both: "OTP and FIDO2 at once (set up by hand): run the setup to pick one",
        unknown: "system-auth isn't readable"
    })[s.mode] ?? s.mode
    readonly property var missing: s ? Object.keys(s.packages ?? {}).filter(p => s.packages[p] === false) : []
    // what the active mode needs from polkit's sandboxed helper
    readonly property var polkitOk: !s ? null : s.mode === "fido2" ? s.polkit?.fido2 : s.mode === "otp" ? s.polkit?.otp : null

    NetCard {
        Layout.fillWidth: true
        title: "YubiKey login"
        icon: "󰌋"
        header: RowLayout {
            spacing: 6
            ActionButton { icon: "󰑓"; text: Yubikey.loading ? "Checking…" : "Reload"; interactive: !Yubikey.loading; onClicked: Yubikey.loadStatus() }
            ActionButton {
                icon: "󰏫"
                text: Yubikey.settingUp ? "Terminal open…" : "Set up / change"
                primary: true
                interactive: !Yubikey.settingUp
                onClicked: Yubikey.setup()
            }
        }
        NetRow {
            first: true
            visible: !page.s
            label: Yubikey.statusError !== "" ? "No status" : "Checking…"
            desc: Yubikey.statusError !== "" ? Yubikey.statusError + " (the dotfiles repo: Maintenance → Dotfiles)" : "yubikey.sh --status --json"
            descError: Yubikey.statusError !== ""
        }
        NetRow {
            first: true
            visible: !!page.s
            label: "Mode"
            desc: page.modeText
            descError: page.s?.mode === "both" || page.s?.mode === "unknown"
            Text {
                text: ({ none: "password", fido2: "FIDO2", otp: "OTP", both: "both", unknown: "?" })[page.s?.mode] ?? ""
                color: page.s?.mode === "none" ? Colors.fade(0.5) : Colors.color6
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
            }
        }
        NetRow {
            visible: !!page.s
            label: "YubiKey"
            desc: page.s?.keyPresent ? "plugged in" + ((page.s.serials ?? []).length ? " · serial " + page.s.serials.join(", ") : "")
                                     : "not plugged in (the password always works)"
        }
        NetRow {
            visible: !!page.s
            label: "Linked to " + (page.s?.user ?? "you")
            desc: "FIDO2: " + (page.s?.linked?.fido2 ?? "unknown") + " key(s) (/etc/u2f_mappings) · OTP: "
                  + (page.s?.linked?.otp ?? "unknown") + " key(s)"
                  + (page.s?.mode === "fido2" ? " · registered for " + page.s.origin + " (renaming the machine needs them linked again)" : "")
        }
        NetRow {
            visible: !!page.s
            label: "FIDO2 PIN"
            desc: page.s?.pin === true ? "set (the key asks for it when a new login is linked, not for logging in)"
                : page.s?.pin === false ? "not set: anyone with the key can link it elsewhere (ykman fido access change-pin)"
                : "unknown (no key plugged in, or ykman missing)"
        }
        NetRow {
            visible: !!page.s && page.polkitOk !== null && page.polkitOk !== undefined
            label: "polkit prompts"
            desc: page.polkitOk ? (page.s.mode === "fido2" ? "its sandboxed helper can reach the key" : "its sandboxed helper can reach YubiCloud")
                                : (page.s?.mode === "fido2" ? "its sandboxed helper can't reach the key: polkit only takes the password"
                                                            : "its sandboxed helper has no network: OTPs fail there")
            descError: !page.polkitOk
        }
        NetRow {
            visible: !!page.s
            label: "Failed logins"
            desc: page.s?.failures === null || page.s?.failures === undefined ? "unknown"
                : page.s.failures + " recent (3 lock the account for 10 min; faillock --user " + page.s.user + " --reset)"
            descError: (page.s?.failures ?? 0) >= 3
        }
        NetRow {
            visible: !!page.s
            label: "Packages"
            desc: page.missing.length === 0 ? "pam-u2f, yubico-pam, libfido2, yubikey-manager installed"
                                            : "not installed: " + page.missing.join(", ") + " (the setup installs what a mode needs)"
        }
        NetRow {
            visible: !!page.s
            label: "Backups"
            desc: (page.s?.backups ?? 0) + " of /etc/pam.d/system-auth (made before every change; the setup can restore one)"
        }
        Repeater {
            model: page.s?.warnings ?? []
            NetRow {
                required property string modelData
                label: "󰀦 Warning"
                desc: modelData
                descError: true
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: "Changes happen in the terminal (yubikey.sh in the dotfiles): it backs up system-auth first, then tests "
              + "your password and the key with sudo and offers to restore the backup. The password keeps working in every mode."
        color: Colors.fade(0.42)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }
}
