import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Updates page (services/Updates.qml): pending updates (repos + AUR), a
// banner when a reboot is needed, Arch news, .pacnew files, and how often to
// check / what to notify about.
ColumnLayout {
    id: page
    spacing: 16

    property bool showAll: false
    // .pacnew / .pacsave: the last remove / overwrite's result, and click-again to confirm
    property string pacnewMsg: ""
    ConfirmArm { id: pacnewArm }
    // a line of pacdiff -o: the .pacnew / .pacsave file itself
    function pacfile(line) { return String(line).trim() }
    readonly property var all: Updates.repo.map(u => Object.assign({ src: "repo" }, u))
                                 .concat(Updates.withAur ? Updates.aurPending.map(u => Object.assign({ src: "AUR" }, u)) : [])

    Component.onCompleted: { Updates.refresh(); Updates.loadNews() }

    NetCard {
        Layout.fillWidth: true
        title: "Updates"
        icon: "󰚰"
        header: [
            ActionButton { icon: "󰑓"; text: Updates.checking ? "Checking…" : "Check now"; interactive: !Updates.checking; onClicked: Updates.refresh() },
            ActionButton { icon: "󰚰"; text: "Upgrade"; primary: true; interactive: Updates.count > 0; onClicked: Updates.upgrade() }
        ]
        // reboot needed: orange banner on top, with the button
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.bottomMargin: 0
            visible: Updates.rebootNeeded
            implicitHeight: rebootRow.implicitHeight + 20
            radius: 10
            color: Qt.rgba(Colors.orange.r, Colors.orange.g, Colors.orange.b, 0.14)
            border.width: 1
            border.color: Qt.rgba(Colors.orange.r, Colors.orange.g, Colors.orange.b, 0.5)
            RowLayout {
                id: rebootRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 10 }
                spacing: 12
                Text { text: "󰜉"; color: Colors.orange; font.pixelSize: 20; font.family: Properties.fontFamily }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Reboot needed"; color: Colors.orange; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily }
                    Text {
                        Layout.fillWidth: true
                        text: "The kernel was updated. Until you reboot, the running kernel's modules are missing (USB sticks, VPNs may fail)."
                        color: Colors.fade(0.6)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }
                ActionButton {
                    id: rebootBtn
                    ConfirmArm { id: rebootArm }
                    readonly property bool armed: rebootArm.armed !== ""
                    icon: "󰜉"
                    text: armed ? "Click again" : "Reboot"
                    textColor: armed ? Colors.red : Colors.ink
                    onClicked: if (rebootArm.confirm("reboot")) Session.reboot()
                }
            }
        }
        NetRow {
            first: !Updates.rebootNeeded
            label: (Updates.count === 0 ? "Up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates"))
                   + (Updates.rebootNeeded ? "  ·  reboot needed" : "")
            desc: (Updates.error !== "" ? "󰀦 " + Updates.error + "  ·  " : "")
                  + Updates.repo.length + " from the repos" + (Updates.withAur ? ", " + Updates.aurPending.length + " from the AUR" : "")
                  + (Updates.aurHeld.length > 0 ? ", " + Updates.aurHeld.length + " on hold" : "")
                  + (Updates.lastCheck > 0 ? "  ·  checked " + new Date(Updates.lastCheck).toLocaleTimeString(Qt.locale(), "HH:mm") : "")
                  + "\nUpgrade opens a terminal: sudo pacman -Syu, then each outdated AUR package on its own (one that fails doesn't stop the others; retry it by hand or put it on hold)"
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
        // AUR packages that failed and wait for a newer version
        Repeater {
            model: Updates.withAur ? Updates.aurHeld : []
            NetRow {
                required property var modelData
                sub: true
                label: "󰏤  " + modelData.name
                desc: modelData.old + "  →  " + modelData.new + "  ·  failed to update, on hold until a newer version comes out"
                RowLayout {
                    spacing: 8
                    Text { text: "on hold"; color: Colors.orange; font.pixelSize: 11; font.family: Properties.fontFamily }
                    ActionButton { text: "Try again"; onClicked: Updates.release(modelData.name) }
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
        // .pacnew / .pacsave: remove (always safe: your file stays), use the new one
        // (your file goes to /var/backups/pacnew/ first), or merge in a terminal.
        // Remove / overwrite run as root through polkit (Updates.pacnewAct)
        NetRow {
            first: true
            label: Updates.pacnew.length === 0 ? "No .pacnew files" : Updates.pacnew.length + " .pacnew / .pacsave files"
            desc: page.pacnewMsg !== "" ? page.pacnewMsg
                : Updates.pacnew.length === 0 ? "config files in /etc are in sync with the packages"
                : "new defaults from packages next to configs you changed. Remove: keeps yours as it is (always safe). "
                  + "Merge opens a terminal (sudo DIFFPROG=\"nvim -d\" pacdiff) to compare side by side"
            RowLayout {
                spacing: 6
                visible: Updates.pacnew.length > 0
                ActionButton {
                    icon: "󰆴"
                    text: Updates.pacnewBusy ? "Working…" : pacnewArm.armed === "all" ? "Remove all " + Updates.pacnew.length + "?" : "Remove all"
                    textColor: pacnewArm.armed === "all" ? Colors.red : Colors.ink
                    interactive: !Updates.pacnewBusy
                    onClicked: if (pacnewArm.confirm("all")) Updates.pacnewAct("remove", Updates.pacnew.map(f => page.pacfile(f)), (ok, msg) => page.pacnewMsg = msg)
                }
                ActionButton { icon: "󰦒"; text: "Merge…"; primary: true; onClicked: Updates.mergePacnew() }
            }
        }
        Repeater {
            model: Updates.pacnew
            NetRow {
                id: pacRow
                required property string modelData
                readonly property string file: page.pacfile(modelData)
                readonly property bool isNew: file.endsWith(".pacnew")
                sub: true
                label: file.replace(/^\/etc\//, "")
                desc: pacnewArm.armed === "new:" + file ? "replaces your " + file.replace(/\.pacnew$/, "") + " with the package's default (yours is kept in /var/backups/pacnew/)"
                    : isNew ? (file.includes("mkinitcpio") ? "careful: your MODULES / HOOKS (nvidia, btrfs, …) would be lost with \"Use new\"; after a change: sudo mkinitcpio -P"
                                                          : "the package's new default, next to your changed file")
                    : "your config from a package that was removed"
                descError: pacnewArm.armed === "new:" + file
                RowLayout {
                    spacing: 6
                    ActionButton {
                        text: pacnewArm.armed === "rm:" + pacRow.file ? "Remove?" : "Remove"
                        textColor: pacnewArm.armed === "rm:" + pacRow.file ? Colors.red : Colors.ink
                        interactive: !Updates.pacnewBusy
                        onClicked: if (pacnewArm.confirm("rm:" + pacRow.file)) Updates.pacnewAct("remove", [pacRow.file], (ok, msg) => page.pacnewMsg = msg)
                    }
                    ActionButton {
                        visible: pacRow.isNew
                        text: pacnewArm.armed === "new:" + pacRow.file ? "Replace mine?" : "Use new"
                        textColor: pacnewArm.armed === "new:" + pacRow.file ? Colors.red : Colors.ink
                        interactive: !Updates.pacnewBusy
                        onClicked: if (pacnewArm.confirm("new:" + pacRow.file)) Updates.pacnewAct("overwrite", [pacRow.file], (ok, msg) => page.pacnewMsg = msg)
                    }
                }
            }
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
        NetRow {
            label: "Notify when a reboot is needed"
            desc: "after a kernel update, with a Reboot now button (the bar's update button also turns orange)"
            ToggleSwitch { checked: Settings.updates.rebootNotify ?? true; onToggled: v => Settings.set("updates", "rebootNotify", v) }
        }
    }
}
