import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Failed services (system and user): what failed, its last log lines,
// restart it or clear the "failed" mark. System units go through pkexec (the
// shell's password prompt); user units don't need a password.
ColumnLayout {
    id: page
    spacing: 16

    property var units: []                  // [{ name, desc, user, log: [] }]
    property bool loading: false
    property string message: ""
    property string expanded: ""

    Component.onCompleted: refresh()

    function valid(u) { return /^[A-Za-z0-9@._:\\-]+\.(service|socket|timer|mount|automount|path|target|scope|slice|swap)$/.test(u) }

    function refresh() {
        loading = true
        const list = []
        let pending = 2
        const done = () => { if (--pending > 0) return; units = list; loading = false; for (const u of list) loadLog(u) }
        for (const user of [false, true])
            Jobs.run(["systemctl"].concat(user ? ["--user"] : []).concat(["--failed", "--no-legend", "--plain", "--no-pager"]), (code, out) => {
                for (const l of out.split("\n")) {
                    const m = /^(\S+)\s+\S+\s+\S+\s+\S+\s+(.*)$/.exec(l.trim())
                    if (m && valid(m[1])) list.push({ name: m[1], desc: m[2], user: user, log: [] })
                }
                done()
            })
    }

    function loadLog(u) {
        Jobs.run(["journalctl"].concat(u.user ? ["--user-unit"] : ["-u"]).concat([u.name, "-n", "12", "--no-pager", "-o", "short-iso", "-b"]), (code, out) => {
            units = units.map(x => x.name === u.name && x.user === u.user ? Object.assign({}, x, { log: out.split("\n").filter(l => l.trim() && !l.startsWith("-- ")) }) : x)
        })
    }

    function act(u, verb) {
        if (!valid(u.name) || !["restart", "reset-failed"].includes(verb)) return
        const argv = u.user ? ["systemctl", "--user", verb, "--", u.name] : ["pkexec", "systemctl", verb, "--", u.name]
        message = (verb === "restart" ? "Restarting " : "Clearing ") + u.name + "…"
        Jobs.run(argv, (code, out, err) => {
            message = code === 0 ? u.name + (verb === "restart" ? " restarted" : ": failed mark cleared")
                    : code === 126 || code === 127 && !u.user ? "cancelled (no password given)" : u.name + ": " + (err.trim().split("\n").pop() || "exit " + code)
            refresh()
        })
    }

    NetCard {
        Layout.fillWidth: true
        title: "Failed services"
        icon: "󰒏"
        header: ActionButton { icon: "󰑓"; text: page.loading ? "Checking…" : "Check again"; onClicked: page.refresh() }
        NetRow {
            first: true
            label: page.loading ? "Checking…" : page.units.length === 0 ? "Nothing failed" : page.units.length + (page.units.length === 1 ? " service failed" : " services failed")
            desc: page.message !== "" ? page.message : "since this boot (systemctl --failed, system and user)"
        }
        Repeater {
            model: page.units
            NetRow {
                id: row
                required property var modelData
                readonly property var u: modelData
                readonly property bool open: page.expanded === u.name
                wide: true
                label: (u.user ? "󰀄 " : "󰒋 ") + u.name + (u.user ? "  ·  user" : "  ·  system")
                desc: u.desc + (u.log.length ? "\n" + (row.open ? u.log : u.log.slice(-3)).join("\n") : "")
                RowLayout {
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    ActionButton { text: row.open ? "Less log" : "More log"; visible: u.log.length > 3; onClicked: page.expanded = row.open ? "" : u.name }
                    ActionButton { icon: "󰜉"; text: "Restart"; onClicked: page.act(u, "restart") }
                    ActionButton { icon: "󰃢"; text: "Clear mark"; onClicked: page.act(u, "reset-failed") }
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Note"
        NetRow {
            first: true
            wide: true
            label: "Not every failed service is a problem"
            desc: "Some only make sense on certain hardware (e.g. the systemd-tpm2 / pcr ones without a TPM chip) and fail harmlessly; \"Clear mark\" hides them until the next boot. To stop one for good: systemctl disable (or mask) it in a terminal."
        }
    }
}
