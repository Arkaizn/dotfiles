import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Updates page (services/Updates.qml): pending updates (repos + AUR), Arch
// news, .pacnew files, reboot needed, and how often to check.
ColumnLayout {
    id: page
    spacing: 16

    property bool showAll: false
    readonly property var all: Updates.repo.map(u => Object.assign({ src: "repo" }, u))
                                 .concat(Updates.withAur ? Updates.aur.map(u => Object.assign({ src: "AUR" }, u)) : [])

    Component.onCompleted: { Updates.refresh(); Updates.loadNews() }

    NetCard {
        Layout.fillWidth: true
        title: "Updates"
        icon: "󰚰"
        header: [
            ActionButton { icon: "󰑓"; text: Updates.checking ? "Checking…" : "Check now"; interactive: !Updates.checking; onClicked: Updates.refresh() },
            ActionButton { icon: "󰚰"; text: "Upgrade"; primary: true; interactive: Updates.count > 0; onClicked: Updates.upgrade() }
        ]
        NetRow {
            first: true
            label: Updates.count === 0 ? "Up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates")
            desc: (Updates.error !== "" ? "󰀦 " + Updates.error + "  ·  " : "")
                  + Updates.repo.length + " from the repos" + (Updates.withAur ? ", " + Updates.aur.length + " from the AUR" : "")
                  + (Updates.lastCheck > 0 ? "  ·  checked " + new Date(Updates.lastCheck).toLocaleTimeString(Qt.locale(), "HH:mm") : "")
                  + "\nUpgrade opens a terminal: sudo pacman -Syu --noconfirm, then the outdated AUR packages with yay"
        }
        Repeater {
            model: page.showAll ? page.all : page.all.slice(0, 12)
            NetRow {
                required property var modelData
                sub: true
                label: modelData.name
                desc: modelData.old + "  →  " + modelData.new
                Text {
                    text: modelData.src
                    color: modelData.src === "AUR" ? Colors.yellow : Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
        }
        NetRow {
            visible: page.all.length > 12
            sub: true
            label: page.showAll ? "Show fewer" : "… and " + (page.all.length - 12) + " more"
            ActionButton { text: page.showAll ? "Fewer" : "Show all"; onClicked: page.showAll = !page.showAll }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "After updating"
        NetRow {
            first: true
            label: Updates.rebootNeeded ? "󰜉  Reboot needed" : "No reboot needed"
            desc: Updates.rebootNeeded ? "the kernel was updated; the running one's modules are gone (USB sticks, VPNs may fail to load modules until you reboot)"
                                       : "the running kernel matches the installed one"
        }
        NetRow {
            wide: Updates.pacnew.length > 0
            label: Updates.pacnew.length === 0 ? "No .pacnew files" : Updates.pacnew.length + " .pacnew / .pacsave files"
            desc: Updates.pacnew.length === 0 ? "config files in /etc are in sync with the packages"
                  : Updates.pacnew.join("\n") + "\nnew defaults from packages next to your changed configs: merge them with  sudo DIFFPROG=\"nvim -d\" pacdiff"
        }
        NetRow {
            wide: Updates.news !== ""
            label: "Arch news"
            desc: !Updates.newsLoaded ? "loading…" : Updates.news === "" ? "nothing new since your last upgrade (yay -Pw)" : Updates.news
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Checking"
        NetRow {
            first: true
            label: "Check every (minutes)"
            desc: Updates.interval === 0 ? "only by hand (Check now)" : "also at login"
            NumberControl { from: 0; to: 360; step: 15; value: Updates.interval; onEdited: v => Settings.set("updates", "interval", Math.round(v)) }
        }
        NetRow {
            label: "Include the AUR"
            desc: "yay -Qua (needs network to the AUR)"
            ToggleSwitch { checked: Updates.withAur; onToggled: v => Settings.set("updates", "aur", v) }
        }
        NetRow {
            label: "Notify about new updates"
            ToggleSwitch { checked: Settings.updates.notify ?? false; onToggled: v => Settings.set("updates", "notify", v) }
        }
    }
}
