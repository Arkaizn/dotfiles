import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "network"

// Lockscreen page: what the lockscreen shows (LockItems.js: notifications with
// text / private / off, media, clock parts, devices, power buttons, blur), and
// which monitor shows the lockscreen; the others show only
// the blurred wallpaper (typing works on every monitor). Monitors are kept by
// "make model serial", like on the Monitors page, so the choice follows a
// monitor to any port and stays while it's unplugged. A monitor without a
// usable identity (unknown, or the same as another connected one) is kept by
// its output name instead (e.g. "DP-3").
//   Settings.lockscreen.monitors: ["<make model serial>" | "<output>", …] in priority order
ColumnLayout {
    id: page
    spacing: 16

    readonly property var chosen: Settings.lockscreen.monitors ?? []
    function save(list) { Settings.set("lockscreen", "monitors", list) }
    function move(i, by) {
        const l = chosen.slice()
        const [m] = l.splice(i, 1)
        l.splice(i + by, 0, m)
        save(l)
    }

    Component.onCompleted: Monitors.refresh()

    // ── what it shows ──
    readonly property var shown: LockItems.resolve(Settings.lockscreen)
    NetCard {
        Layout.fillWidth: true
        title: "Show on the lockscreen"
        icon: "󰈈"
        Repeater {
            model: LockItems.items
            NetRow {
                id: itemRow
                required property var modelData
                required property int index
                first: index === 0
                sub: modelData.parent !== undefined
                visible: !modelData.parent || page.shown[modelData.parent] === true
                label: modelData.label
                desc: modelData.desc
                changed: page.shown[modelData.key] !== modelData.def
                ToggleSwitch {
                    visible: itemRow.modelData.kind === "bool"
                    checked: page.shown[itemRow.modelData.key] === true
                    onToggled: v => v === itemRow.modelData.def ? Settings.reset("lockscreen", itemRow.modelData.key)
                                                                : Settings.set("lockscreen", itemRow.modelData.key, v)
                }
                DropdownControl {
                    visible: itemRow.modelData.kind === "choice"
                    implicitWidth: 160
                    options: itemRow.modelData.choices ?? []
                    value: page.shown[itemRow.modelData.key]
                    onEdited: v => v === itemRow.modelData.def ? Settings.reset("lockscreen", itemRow.modelData.key)
                                                               : Settings.set("lockscreen", itemRow.modelData.key, v)
                }
            }
        }
    }

    // what an entry stores for a connected monitor
    function keyFor(o) {
        const unique = Monitors.outputs.filter(x => x.ident === o.ident).length === 1
        return unique && !o.ident.startsWith("Unknown Unknown") ? o.ident : o.name
    }
    // the output name of a monitor if it's connected now, else ""
    function connectedName(id) {
        const o = Monitors.outputs.find(x => x.ident === id || x.name === id)
        return o && Quickshell.screens.some(s => s.name === o.name) ? o.name : ""
    }
    // "make model serial" without an unknown serial
    function label(id) { return id.replace(/ Unknown$/, "") }

    // every monitor the shell knows: connected now, saved on the Monitors page, or already chosen
    readonly property var known: {
        const ids = Object.keys(Settings.monitors ?? {}).filter(id => !id.startsWith("Unknown Unknown"))
            .concat(Monitors.outputs.map(o => page.keyFor(o))).concat(chosen)
        return ids.filter((id, i) => ids.indexOf(id) === i)
    }
    readonly property string usedNow: {
        const hit = chosen.find(id => connectedName(id) !== "")
        return hit ? connectedName(hit) : ""
    }

    NetCard {
        Layout.fillWidth: true
        title: "Show the lockscreen on"
        icon: "󰌾"

        NetRow {
            first: true
            visible: page.chosen.length === 0
            label: "All monitors"
            desc: "Add a monitor below to show the lockscreen on that one only; the others then show the blurred wallpaper"
        }

        Repeater {
            model: page.chosen
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: (index + 1) + ".  " + page.label(modelData)
                desc: page.connectedName(modelData) === "" ? "not connected"
                    : "connected (" + page.connectedName(modelData) + ")" + (page.usedNow === page.connectedName(modelData) ? "  ·  used now" : "")
                RowLayout {
                    spacing: 4
                    IconButton {
                        icon: "󰁝"
                        tooltip: "Higher"
                        interactive: index > 0
                        onClicked: page.move(index, -1)
                    }
                    IconButton {
                        icon: "󰁅"
                        tooltip: "Lower"
                        interactive: index < page.chosen.length - 1
                        onClicked: page.move(index, 1)
                    }
                    IconButton {
                        icon: "󰅖"
                        tooltip: "Remove"
                        onClicked: page.save(page.chosen.filter(x => x !== modelData))
                    }
                }
            }
        }

        NetRow {
            visible: page.chosen.length > 0
            label: "None of them connected"
            desc: "The lockscreen shows on the monitor you were using when it locked, and moves over as soon as one of the monitors above is plugged in"
        }

        NetRow {
            id: addRow
            readonly property var free: page.known.filter(id => !page.chosen.includes(id))
            visible: free.length > 0
            label: "Add a monitor"
            desc: "Connected now or saved on the Monitors page"
            DropdownControl {
                implicitWidth: 300
                options: addRow.free.map(id => ({ label: page.label(id) + (page.connectedName(id) !== "" ? "  (" + page.connectedName(id) + ")" : ""), value: id }))
                value: ""
                onEdited: v => page.save(page.chosen.concat([v]))
            }
        }
    }
}
