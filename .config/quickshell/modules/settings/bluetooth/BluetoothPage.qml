import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.components
import qs.services
import ".."
import "../network"

// Bluetooth page (native Quickshell.Bluetooth): the adapter (power, name,
// discoverable, pairable) and paired devices (connect, trust = reconnects by
// itself, block, rename, forget). Pairing new devices: control center.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var paired: (adapter?.devices.values ?? []).filter(d => d.paired || d.bonded)
                                    .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    property string renaming: ""           // device address being renamed
    property string confirmForget: ""

    NetCard {
        Layout.fillWidth: true
        visible: !page.adapter
        title: "No Bluetooth adapter"
        icon: "󰂲"
        NetRow {
            first: true
            wide: true
            label: "BlueZ doesn't report an adapter"
            desc: "Is the service running and the adapter plugged in?  systemctl enable --now bluetooth   ·   " + Jobs.installHint("bluetoothctl")
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: !!page.adapter
        title: "Adapter"
        icon: "󰂯"
        NetRow {
            first: true
            label: "Bluetooth"
            desc: BluetoothPower.blocked ? "blocked by rfkill: turning it on unblocks it" : (page.adapter?.enabled ? "on" : "off")
            ToggleSwitch { checked: BluetoothPower.enabled; onToggled: v => BluetoothPower.setEnabled(v) }
        }
        NetRow {
            label: "Name"
            desc: "what other devices see"
            TextControl {
                value: page.adapter?.name ?? ""
                onEdited: v => { const n = v.trim(); if (n !== "" && n.length <= 60 && page.adapter) page.adapter.name = n }
            }
        }
        NetRow {
            label: "Visible to other devices"
            desc: page.adapter?.discoverable ? "discoverable for " + Math.round((page.adapter?.discoverableTimeout ?? 0) / 60) + " min (0 = until turned off)" : "only paired devices can find it"
            ToggleSwitch {
                checked: page.adapter?.discoverable ?? false
                enabled: page.adapter?.enabled ?? false
                onToggled: v => { if (page.adapter) page.adapter.discoverable = v }
            }
        }
        NetRow {
            label: "Accept pairing"
            ToggleSwitch {
                checked: page.adapter?.pairable ?? false
                enabled: page.adapter?.enabled ?? false
                onToggled: v => { if (page.adapter) page.adapter.pairable = v }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: !!page.adapter
        title: "Paired devices"
        NetRow {
            first: true
            visible: page.paired.length === 0
            label: "No paired devices"
            desc: "pair one from the control center (Bluetooth → search)"
        }
        Repeater {
            model: page.paired
            NetRow {
                id: row
                required property var modelData
                required property int index
                readonly property var dev: modelData
                first: index === 0
                wide: true
                label: BluetoothPower.iconFor(dev) + "  " + dev.name + (dev.connected ? "  ·  connected" : "")
                desc: dev.address
                      + (dev.icon ? "  ·  " + dev.icon.replace(/-/g, " ") : "")
                      + (dev.batteryAvailable ? "  ·  battery " + Math.round(dev.battery * 100) + "%" : "")
                      + (dev.trusted ? "  ·  trusted (reconnects by itself)" : "")
                      + (dev.blocked ? "  ·  blocked" : "")
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    ActionButton {
                        text: dev.connected ? "Disconnect" : dev.state === BluetoothDeviceState.Connecting ? "Connecting…" : "Connect"
                        interactive: (page.adapter?.enabled ?? false) && !dev.blocked
                        onClicked: dev.connected ? dev.disconnect() : dev.connect()
                    }
                    SearchField {
                        id: nameField
                        Layout.fillWidth: true
                        visible: page.renaming === dev.address
                        icon: ""
                        placeholderText: dev.deviceName
                        onAccepted: { if (text.trim() !== "") dev.name = text.trim().slice(0, 60); page.renaming = "" }
                    }
                    Item { Layout.fillWidth: true; visible: page.renaming !== dev.address }
                    IconButton {
                        icon: page.renaming === dev.address ? "󰄬" : "󰏫"
                        tooltip: page.renaming === dev.address ? "Save the name" : "Rename"
                        onClicked: {
                            if (page.renaming === dev.address) { if (nameField.text.trim() !== "") dev.name = nameField.text.trim().slice(0, 60); page.renaming = "" }
                            else { nameField.text = dev.name; page.renaming = dev.address; nameField.forceActiveFocus() }
                        }
                    }
                    IconButton {
                        icon: dev.trusted ? "󰒘" : "󰒙"
                        active: dev.trusted
                        tooltip: dev.trusted ? "Trusted: reconnects by itself (click to stop)" : "Trust: let it reconnect by itself"
                        onClicked: dev.trusted = !dev.trusted
                    }
                    IconButton {
                        icon: "󰂭"
                        active: dev.blocked
                        textColor: dev.blocked ? Colors.red : Properties.color
                        tooltip: dev.blocked ? "Blocked: can't connect (click to unblock)" : "Block"
                        onClicked: dev.blocked = !dev.blocked
                    }
                    IconButton {
                        icon: page.confirmForget === dev.address ? "󰄬" : "󰆴"
                        textColor: page.confirmForget === dev.address ? Colors.red : Properties.color
                        tooltip: page.confirmForget === dev.address ? "Click again to forget it" : "Forget (unpair)"
                        onClicked: {
                            if (page.confirmForget === dev.address) { dev.forget(); page.confirmForget = "" }
                            else { page.confirmForget = dev.address; forgetTimer.restart() }
                        }
                    }
                }
            }
        }
    }
    Timer { id: forgetTimer; interval: 3000; onTriggered: page.confirmForget = "" }
}
