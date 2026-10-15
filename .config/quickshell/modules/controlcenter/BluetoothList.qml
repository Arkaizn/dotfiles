import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.components
import qs.services

// Bluetooth device list: scan, pair, connect/disconnect, forget.
ColumnLayout {
    id: root

    property bool active: false    // scan only while the list is shown
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int maxListHeight: 260

    spacing: 6

    // Discover new devices while the list is open
    onActiveChanged: if (adapter?.enabled) adapter.discovering = active

    // connected, then paired, then named, then the rest
    readonly property var devices: (adapter?.devices?.values ?? [])
        .filter(d => d.paired || d.connected || (d.name && d.name !== d.address.replace(/:/g, "-")))
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired)
                        || (a.name || "").localeCompare(b.name || ""))

    function deviceIcon(d) {
        const i = d.icon || ""
        if (i.includes("headset") || i.includes("headphone")) return "󰋋"
        if (i.includes("audio")) return "󰓃"
        if (i.includes("mouse")) return "󰍽"
        if (i.includes("keyboard")) return "󰌌"
        if (i.includes("phone")) return "󰏲"
        if (i.includes("gaming") || i.includes("joystick")) return "󰊴"
        if (i.includes("computer")) return "󰟀"
        return "󰂯"
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: !root.adapter ? "No Bluetooth adapter"
                : !root.adapter.enabled ? "Bluetooth is off"
                : root.adapter.discovering ? "Searching for devices…"
                : root.devices.length + " devices"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 11
        }
        IconButton {
            implicitWidth: 26; implicitHeight: 26
            visible: root.adapter?.enabled ?? false
            icon: "󰑐"
            active: root.adapter?.discovering ?? false
            tooltip: root.adapter?.discovering ? "Stop searching" : "Search for devices"
            onClicked: root.adapter.discovering = !root.adapter.discovering
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.implicitHeight, root.maxListHeight)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: list
            width: parent.width
            spacing: 4

            Repeater {
                model: root.adapter?.enabled ? root.devices : []

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var dev: modelData
                    readonly property bool busy: dev.pairing
                        || dev.state === BluetoothDeviceState.Connecting
                        || dev.state === BluetoothDeviceState.Disconnecting

                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 10
                    color: dev.connected ? Qt.rgba(1, 1, 1, 0.12)
                         : rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }

                    function activate() {
                        if (busy) return
                        if (dev.connected) dev.disconnect()
                        else if (dev.paired) dev.connect()
                        else dev.pair()
                    }

                    // freshly paired → trust it so it reconnects, then connect
                    Connections {
                        target: row.dev
                        function onPairedChanged() {
                            if (!row.dev.paired) return
                            row.dev.trusted = true
                            row.dev.connect()
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.activate()
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                        spacing: 8

                        Text {
                            text: root.deviceIcon(row.dev)
                            color: "white"
                            font.pixelSize: 15
                            font.family: Properties.fontFamily
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.dev.name || row.dev.address
                                color: "white"
                                font.pixelSize: 12
                                font.bold: row.dev.connected
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.dev.pairing ? "Pairing…"
                                    : row.dev.state === BluetoothDeviceState.Connecting ? "Connecting…"
                                    : row.dev.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                                    : row.dev.connected ? "Connected" + (row.dev.batteryAvailable ? " · " + Math.round(row.dev.battery * 100) + "%" : "")
                                    : row.dev.paired ? "Paired" : "Click to pair"
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pixelSize: 10
                            }
                        }
                        IconButton {
                            visible: row.dev.paired
                            implicitWidth: 26; implicitHeight: 26
                            icon: "󰆴"
                            tooltip: "Forget"
                            onClicked: row.dev.forget()
                        }
                    }
                }
            }
        }
    }
}
