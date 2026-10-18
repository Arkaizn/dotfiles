import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Installed packages: totals, the biggest ones (all / installed by you /
// dependencies / AUR), and what was recently installed, updated or removed
// (/var/log/pacman.log). Read-only.
ColumnLayout {
    id: page
    spacing: 16

    property var pkgs: []                   // [{ name, size, explicit, date, aur }]
    property var history: []                // [{ time, action, name, version }]
    property string kind: "all"             // all | explicit | deps | aur
    property string query: ""
    property bool loading: true
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return pkgs.filter(p => (kind === "all" || (kind === "explicit" && p.explicit) || (kind === "deps" && !p.explicit) || (kind === "aur" && p.aur))
                              && (q === "" || p.name.includes(q)))
    }
    readonly property real totalSize: pkgs.reduce((a, p) => a + p.size, 0)

    Component.onCompleted: load()

    function load() {
        loading = true
        Jobs.run(["pacman", "-Qmq"], (c0, aurOut) => {
            const aur = aurOut.split("\n").filter(x => x)
            Jobs.run(["pacman", "-Qi"], (code, out) => {
                const list = []
                let cur = null
                const unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824 }
                for (const l of out.split("\n")) {
                    let m
                    if ((m = /^Name\s*:\s*(\S+)/.exec(l))) { cur = { name: m[1], size: 0, explicit: false, date: "", aur: aur.includes(m[1]) }; list.push(cur) }
                    else if (!cur) continue
                    else if ((m = /^Installed Size\s*:\s*([\d.]+)\s*(\w+)/.exec(l))) cur.size = Number(m[1]) * (unit[m[2]] ?? 1)
                    else if ((m = /^Install Reason\s*:\s*(.*)$/.exec(l))) cur.explicit = m[1].startsWith("Explicitly")
                    else if ((m = /^Install Date\s*:\s*(.*)$/.exec(l))) cur.date = m[1].trim()
                }
                pkgs = list.sort((a, b) => b.size - a.size)
                loading = false
            }, { LC_ALL: "C" })
        })
        Jobs.run(["tail", "-n", "3000", "/var/log/pacman.log"], (code, out) => {
            history = out.split("\n").map(l => /^\[([^\]]+)\] \[ALPM\] (installed|upgraded|removed|downgraded) (\S+) \((.*)\)$/.exec(l))
                         .filter(m => m).map(m => ({ time: m[1].replace("T", " ").slice(0, 16), action: m[2], name: m[3], version: m[4] }))
                         .reverse().slice(0, 40)
        })
    }

    NetCard {
        Layout.fillWidth: true
        title: "Installed"
        icon: "󰏗"
        header: ActionButton { icon: "󰑓"; text: page.loading ? "Reading…" : "Reload"; onClicked: page.load() }
        NetRow {
            first: true
            label: page.loading ? "Reading the package database…" : page.pkgs.length + " packages  ·  " + PerfMon.bytes(page.totalSize)
            desc: page.pkgs.filter(p => p.explicit).length + " installed by you, " + page.pkgs.filter(p => !p.explicit).length
                  + " as dependencies, " + page.pkgs.filter(p => p.aur).length + " from the AUR / not in the repos"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Biggest packages"
        NetRow {
            first: true
            label: "Show"
            RowLayout {
                spacing: 8
                Segmented {
                    small: true
                    options: [{ label: "All", value: "all" }, { label: "Yours", value: "explicit" }, { label: "Dependencies", value: "deps" }, { label: "AUR / local", value: "aur" }]
                    value: page.kind
                    onEdited: v => page.kind = v
                }
                SearchField { Layout.preferredWidth: 180; text: page.query; onTextEdited: page.query = text; placeholderText: "name" }
            }
        }
        Repeater {
            model: page.shown.slice(0, 30)
            NetRow {
                required property var modelData
                sub: true
                label: modelData.name + (modelData.aur ? "  ·  AUR / not in repos" : "") + (modelData.explicit ? "" : "  ·  dependency")
                desc: "installed " + modelData.date
                RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 120 * Math.min(1, modelData.size / Math.max(1, page.shown[0]?.size ?? 1))
                        implicitHeight: 6; radius: 3; color: Colors.color6
                    }
                    Text { Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; text: PerfMon.bytes(modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                }
            }
        }
        NetRow {
            visible: page.shown.length > 30
            sub: true
            label: "… and " + (page.shown.length - 30) + " more (search to find one)"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Recently changed"
        NetRow {
            first: true
            visible: page.history.length === 0
            label: "Nothing in /var/log/pacman.log"
        }
        Repeater {
            model: page.history
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.name
                desc: modelData.version
                RowLayout {
                    spacing: 10
                    Text {
                        text: modelData.action
                        color: modelData.action === "removed" ? Colors.red : modelData.action === "installed" ? Colors.green : Colors.fade(0.6)
                        font.pixelSize: 11; font.family: Properties.fontFamily
                    }
                    Text { text: modelData.time; color: Colors.fade(0.45); font.pixelSize: 11; font.family: Properties.fontFamily }
                }
            }
        }
    }
}
