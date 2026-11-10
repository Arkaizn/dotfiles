import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Failed services (system and user): what failed, its last log lines,
// restart it (or all of them) or clear the "failed" mark. System units go
// through pkexec (the shell's password prompt); user units don't need a
// password. The list and the actions live in services/FailedUnits.qml (it
// also sends the "services failed" notification).
ColumnLayout {
    id: page
    spacing: Tokens.space.s16

    readonly property var units: FailedUnits.units
    readonly property bool loading: FailedUnits.loading
    property string expanded: ""

    Component.onCompleted: FailedUnits.refresh()

    Section {
        Layout.fillWidth: true
        title: "Failed services"
        icon: "󰒏"
        header: RowLayout {
            spacing: Tokens.space.s6
            ActionButton {
                icon: "󰜉"
                text: FailedUnits.busy ? "Restarting…" : "Restart all"
                visible: page.units.length > 0 || FailedUnits.busy
                enabled: !FailedUnits.busy
                onClicked: FailedUnits.restartAll()
            }
            ActionButton { icon: "󰑓"; text: page.loading ? "Checking…" : "Check again"; onClicked: FailedUnits.refresh() }
        }
        SettingRow {
            first: true
            label: page.loading ? "Checking…" : page.units.length === 0 ? "Nothing failed" : page.units.length + (page.units.length === 1 ? " service failed" : " services failed")
            desc: FailedUnits.message !== "" ? FailedUnits.message : "since this boot (systemctl --failed, system and user)"
        }
        Repeater {
            model: page.units
            SettingRow {
                id: row
                required property var modelData
                readonly property var u: modelData
                readonly property bool open: page.expanded === u.name
                wide: true
                label: (u.user ? "󰀄 " : "󰒋 ") + u.name + (u.user ? "  ·  user" : "  ·  system")
                desc: u.desc + (u.log.length ? "\n" + (row.open ? u.log : u.log.slice(-3)).join("\n") : "")
                RowLayout {
                    spacing: Tokens.space.s6
                    Item { Layout.fillWidth: true }
                    ActionButton { text: row.open ? "Less log" : "More log"; visible: u.log.length > 3; onClicked: page.expanded = row.open ? "" : u.name }
                    ActionButton { icon: "󰜉"; text: "Restart"; onClicked: FailedUnits.act(u, "restart") }
                    ActionButton { icon: "󰃢"; text: "Clear mark"; onClicked: FailedUnits.act(u, "reset-failed") }
                }
            }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Notifications"
        icon: "󰂚"
        SettingRow {
            first: true
            label: "Notify when a service fails"
            desc: "30 s after login (what failed during boot), then every 5 minutes for new failures; with a \"Restart all\" button (asks for the password)"
            ToggleSwitch {
                checked: FailedUnits.notify
                onToggled: v => Settings.set("health", "failedNotify", v)
            }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Note"
        SettingRow {
            first: true
            wide: true
            label: "Not every failed service is a problem"
            desc: "Some only make sense on certain hardware (e.g. the systemd-tpm2 / pcr ones without a TPM chip) and fail harmlessly; \"Clear mark\" hides them until the next boot. To stop one for good: systemctl disable (or mask) it in a terminal."
        }
    }
}
