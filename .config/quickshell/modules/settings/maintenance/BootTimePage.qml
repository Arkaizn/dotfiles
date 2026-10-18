import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Boot time (systemd-analyze): how long each stage took, what was on the
// critical path (what actually made you wait), and the slowest units.
// Read-only.
ColumnLayout {
    id: page
    spacing: 16

    property var stages: []                 // [{ name, secs }]
    property real total: 0
    property var blame: []                  // [{ unit, secs }]
    property var userBlame: []
    property var chain: []                  // unit names on the critical chain
    property string chainText: ""
    property string error: ""

    Component.onCompleted: load()

    function secs(t) {                      // "1min 2.5s" / "850ms" / "3.301s"
        let s = 0, m
        const re = /([\d.]+)\s*(min|ms|s|h)/g
        while ((m = re.exec(t))) s += Number(m[1]) * ({ h: 3600, min: 60, s: 1, ms: 0.001 }[m[2]])
        return s
    }

    function load() {
        Jobs.run(["systemd-analyze"], (code, out, err) => {
            const m = /Startup finished in (.*?) = ([^\n]+)/.exec(out)
            if (!m) { error = (err || out).trim().split("\n")[0] || "systemd-analyze failed"; return }
            stages = m[1].split(" + ").map(p => { const x = /^(.*?)\s*\((\w+)\)$/.exec(p.trim()); return x ? { name: x[2], secs: secs(x[1]) } : null }).filter(x => x)
            total = secs(m[2])
        })
        const parseBlame = out => out.split("\n").map(l => /^\s*(.+?)\s+(\S+\.(?:service|mount|socket|device|target|timer|swap|slice|scope))$/.exec(l))
                                      .filter(x => x).map(x => ({ unit: x[2], secs: secs(x[1]) })).slice(0, 15)
        Jobs.run(["systemd-analyze", "blame", "--no-pager"], (c, o) => blame = parseBlame(o))
        Jobs.run(["systemd-analyze", "--user", "blame", "--no-pager"], (c, o) => userBlame = parseBlame(o).slice(0, 8))
        Jobs.run(["systemd-analyze", "critical-chain", "--no-pager"], (c, o) => {
            chainText = o.replace(/\x1b\[[0-9;]*m/g, "").split("\n").filter(l => /[└├│]|\.target|\.service/.test(l)).slice(0, 14).join("\n")
            chain = (chainText.match(/[\w@.\\-]+\.(service|mount|socket|target|device)/g) ?? [])
        })
    }

    readonly property var colors: ({ firmware: "#89b4fa", loader: "#94e2d5", kernel: "#f9e2af", initrd: "#fab387", userspace: Colors.color6 })

    NetCard {
        Layout.fillWidth: true
        title: "Last boot"
        icon: "󰑮"
        header: ActionButton { icon: "󰑓"; text: "Reload"; onClicked: page.load() }
        NetRow {
            first: true
            wide: true
            label: page.error !== "" ? page.error : page.total.toFixed(1) + " s from power on to the desktop"
            desc: page.stages.map(s => s.name + " " + s.secs.toFixed(1) + " s").join("  ·  ")
                  + "\nfirmware = BIOS / UEFI (not something Linux can speed up), loader = boot menu, userspace = services"
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 14
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.06)
                clip: true
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: page.stages
                        Rectangle {
                            required property var modelData
                            width: parent.width * modelData.secs / Math.max(0.1, page.total)
                            height: parent.height
                            color: page.colors[modelData.name] ?? Qt.rgba(1, 1, 1, 0.3)
                        }
                    }
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "What made you wait (critical chain)"
        NetRow {
            first: true
            wide: true
            label: "Each line waited for the one below it; +time = how long that unit took"
            desc: page.chainText || "…"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Slowest system units"
        NetRow {
            first: true
            wide: true
            label: "Most run in parallel or after login"
            desc: "units marked 󰔛 were on the critical chain above; the others didn't delay the desktop"
        }
        Repeater {
            model: page.blame
            NetRow {
                required property var modelData
                sub: true
                label: (page.chain.includes(modelData.unit) ? "󰔛 " : "") + modelData.unit
                RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 120 * Math.min(1, modelData.secs / Math.max(0.1, page.blame[0]?.secs ?? 1))
                        implicitHeight: 6; radius: 3
                        color: page.chain.includes(modelData.unit) ? "#f9e2af" : Colors.color6
                    }
                    Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: modelData.secs.toFixed(2) + " s"; color: "white"; font.pixelSize: 12; font.family: Properties.fontFamily }
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: page.userBlame.length > 0
        title: "Slowest user units (after login)"
        Repeater {
            model: page.userBlame
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.unit
                Text { text: modelData.secs.toFixed(2) + " s"; color: "white"; font.pixelSize: 12; font.family: Properties.fontFamily }
            }
        }
    }
}
