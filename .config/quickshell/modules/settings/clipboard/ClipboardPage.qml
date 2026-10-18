import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Clipboard page (services/Clipboard.qml): history on / paused, size, wipe,
// and the password manager protection (KeePassXC).
ColumnLayout {
    id: page
    spacing: 16

    property bool confirmWipe: false
    Component.onCompleted: Clipboard.refresh()

    NetCard {
        Layout.fillWidth: true
        title: "History"
        NetRow {
            first: true
            label: Clipboard.watching ? "Recording copies" : "Paused"
            desc: Clipboard.watching ? Clipboard.count + " entries  ·  open with the launcher's clipboard tab (Super+V)"
                                     : "nothing new is stored until you resume (or the next login)"
            ActionButton {
                icon: Clipboard.watching ? "󰏤" : "󰐊"
                text: Clipboard.watching ? "Pause" : "Resume"
                onClicked: Clipboard.watching ? Clipboard.pause() : Clipboard.resume()
            }
        }
        NetRow {
            label: "Keep at most"
            desc: "entries (oldest go first)"
            NumberControl {
                from: 10; to: 5000; step: 10
                value: Number(Clipboard.options["max-items"] ?? 750)
                onEdited: v => Clipboard.setOption("max-items", v)
            }
        }
        NetRow {
            label: "Ignore copies shorter than"
            desc: "characters (0 = keep everything)"
            NumberControl {
                from: 0; to: 20
                value: Number(Clipboard.options["min-store-length"] ?? 0)
                onEdited: v => Clipboard.setOption("min-store-length", v)
            }
        }
        NetRow {
            label: "Clear the history"
            desc: page.confirmWipe ? "all " + Clipboard.count + " entries are deleted, click again" : "also happens at every login (startup.kdl: cliphist wipe)"
            ActionButton {
                icon: "󰃢"
                text: page.confirmWipe ? "Delete all" : "Clear…"
                textColor: page.confirmWipe ? Colors.red : Colors.ink
                onClicked: {
                    if (page.confirmWipe) { Clipboard.wipe(); page.confirmWipe = false }
                    else { page.confirmWipe = true; wipeTimer.restart() }
                }
                Timer { id: wipeTimer; interval: 4000; onTriggered: page.confirmWipe = false }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Passwords"
        icon: Clipboard.protectedPasswords ? "󰌾" : "󰀦"
        NetRow {
            first: true
            wide: true
            label: !Clipboard.loaded ? "Checking…" : Clipboard.protectedPasswords ? "Copied passwords are not stored" : "Copied passwords may end up in the history"
            desc: "KeePassXC marks copied passwords as secret (x-kde-passwordManagerHint); wl-paste " + (Clipboard.wlVersion || "?")
                  + " passes that on and cliphist " + (Clipboard.cliphistVersion || "?") + " skips them"
                  + (Clipboard.protectedPasswords ? " (tested here: a marked copy was not stored)." : ". Needs wl-clipboard ≥ 2.2 and cliphist ≥ 0.6.")
        }
        NetRow {
            wide: true
            label: "In KeePassXC"
            desc: "Settings → Security → “Clear clipboard after” (e.g. 10 s), so a password doesn't stay in the clipboard itself. Browser autofill (KeePassXC-Browser) avoids the clipboard completely."
        }
    }
}
