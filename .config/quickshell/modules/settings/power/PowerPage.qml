import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.components
import qs.services
import ".."
import "../network"

// Power page (services/Power.qml): the power profile, what holds it, and
// power saver on battery.
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: Power.check()

    NetCard {
        Layout.fillWidth: true
        visible: Power.checked && Power.available.length === 0
        title: "Power profiles unavailable"
        icon: "󰀦"
        NetRow { first: true; wide: true; label: "power-profiles-daemon"; desc: Power.error + "   ·   it starts by itself over D-Bus once installed" }
    }

    NetCard {
        Layout.fillWidth: true
        visible: Power.available.length > 0
        title: "Power profile"
        NetRow {
            first: true
            label: Power.labels[Power.current]
            desc: Power.current === "performance" ? "fastest, more power and heat"
                : Power.current === "power-saver" ? "slower, less power and heat" : "the default"
            Segmented {
                small: true
                options: Power.available.map(n => ({ label: Power.labels[n], value: n, icon: Power.icons[n] }))
                value: Power.current
                onEdited: v => Power.set(v)
            }
        }
        NetRow {
            visible: Power.degraded !== ""
            label: "Performance is limited"
            desc: "because " + Power.degraded
        }
        NetRow {
            visible: PowerProfiles.holds.length > 0
            wide: true
            label: "Held by apps"
            desc: PowerProfiles.holds.map(h => h.applicationId + " → " + PowerProfile.toString(h.profile) + (h.reason ? " (" + h.reason + ")" : "")).join("\n")
        }
        NetRow {
            label: "On the bar"
            desc: "add “Power profile” in Bar layout; click it to switch.  qs ipc call power cycle"
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: Power.available.length > 0
        title: "Battery"
        NetRow {
            first: true
            label: "Power saver on battery"
            desc: Power.hasBattery ? "back to the previous profile when plugged in" : "this computer has no battery"
            ToggleSwitch {
                enabled: Power.hasBattery
                checked: Settings.power.batterySaver ?? false
                onToggled: v => Settings.set("power", "batterySaver", v)
            }
        }
    }
}
