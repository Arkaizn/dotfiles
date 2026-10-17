import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../notifications"

// Control center (right side of the bar): time + power, Wi-Fi, Bluetooth,
// tools (screenshot, OCR, color picker), batteries, volume, notifications.
// Window/shape/animation all come from BarPopup.
BarPopup {
    id: root
    side: "right"
    ipcName: "controlCenter"
    panelWidth: 420
    // grows with the content up to the screen height, then scrolls
    maxHeight: (screen?.height ?? 1440) - 90
    panelHeight: Math.min(mainCol.implicitHeight + padding * 2, maxHeight)
    // don't vanish while typing a Wi-Fi password with the pointer elsewhere
    autoClose: wifiList.passwordFor === ""

    // needed for the Wi-Fi password field
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // old name, so existing keybinds keep working
    IpcHandler {
        target: "notifCenter"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    property string expanded: ""   // "" | "wifi" | "bluetooth"

    // Switching directly between the two lists slides the new one in from
    // the side its tile is on (Wi-Fi left, Bluetooth right). Opening from
    // closed just grows the card instead.
    property string prevExpanded: ""
    onExpandedChanged: {
        const from = prevExpanded
        prevExpanded = expanded
        if (from === "" || expanded === "") return
        listSlide.stop()
        listSlide.target = expanded === "wifi" ? wifiList : btList
        listSlide.from = expanded === "wifi" ? -60 : 60
        listSlide.start()
    }

    ParallelAnimation {
        id: listSlide
        property Item target: null
        property real from: 0
        NumberAnimation { target: listSlide.target; property: "slideX"; from: listSlide.from; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: listSlide.target; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    // every dropdown starts closed again on the next open
    onPopupClosed: {
        expanded = ""
        wifiList.passwordFor = ""
        audioCard.reset()
        Notifs.collapseAll()
    }

    // ── Network / Bluetooth state ──
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var wifiNetwork: wifiDevice?.networks?.values.find(n => n.connected) ?? null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: (btAdapter?.devices?.values ?? []).filter(d => d.connected)

    // Close first, so the panel isn't in the screenshot / color pick
    function runTool(cmd) {
        root.close()
        Quickshell.execDetached(["bash", "-c", "sleep 0.35; " + cmd])
    }


    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: mainCol
            width: flick.width
            spacing: 8

            // ── Time + power ──
            CCCard {
                Layout.fillWidth: true
                implicitHeight: header.implicitHeight + 24
                CCHeader {
                    id: header
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    onActionStarted: root.close()
                }
            }

            // ── Wi-Fi + Bluetooth tiles ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QuickTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: !Networking.wifiEnabled ? "󰤮"
                        : root.wifiNetwork ? "󰤨"
                        : root.wiredDevice?.connected ? "󰈀" : "󰤯"
                    title: "Wi-Fi"
                    subtitle: !root.wifiDevice ? (root.wiredDevice?.connected ? "Ethernet" : "No Wi-Fi device")
                        : !Networking.wifiEnabled ? (root.wiredDevice?.connected ? "Off · Ethernet" : "Off")
                        : root.wifiNetwork ? root.wifiNetwork.name
                        : root.wiredDevice?.connected ? "Ethernet" : "Not connected"
                    active: Networking.wifiEnabled && root.wifiDevice !== null
                    expanded: root.expanded === "wifi"
                    expandable: root.wifiDevice !== null
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    onExpandClicked: root.expanded = expanded ? "" : "wifi"
                }

                QuickTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: !root.btAdapter?.enabled ? "󰂲" : root.btConnected.length > 0 ? "󰂱" : "󰂯"
                    title: "Bluetooth"
                    subtitle: !root.btAdapter ? "No adapter"
                        : !root.btAdapter.enabled ? "Off"
                        : root.btConnected.length === 1 ? root.btConnected[0].name
                        : root.btConnected.length > 1 ? root.btConnected.length + " devices"
                        : "On"
                    active: root.btAdapter?.enabled ?? false
                    expanded: root.expanded === "bluetooth"
                    expandable: root.btAdapter !== null
                    onToggled: BluetoothPower.toggle()
                    onExpandClicked: root.expanded = expanded ? "" : "bluetooth"
                }
            }

            // ── Wi-Fi / Bluetooth details (one at a time) ──
            CCCard {
                id: detailCard
                Layout.fillWidth: true
                readonly property real target: root.expanded === "wifi" ? wifiList.implicitHeight + 24
                                              : root.expanded === "bluetooth" ? btList.implicitHeight + 24 : 0
                implicitHeight: target
                visible: implicitHeight > 0.5
                clip: true
                Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                WifiList {
                    id: wifiList
                    property real slideX: 0
                    transform: Translate { x: wifiList.slideX }
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    visible: root.expanded === "wifi"
                    device: root.wifiDevice
                    active: visible && root.shown
                }
                BluetoothList {
                    id: btList
                    property real slideX: 0
                    transform: Translate { x: btList.slideX }
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    visible: root.expanded === "bluetooth"
                    active: visible && root.shown
                }
            }

            // ── Tools ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QuickTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    expandable: false
                    icon: "󰹑"
                    title: "Capture"
                    subtitle: "Screenshot"
                    onToggled: root.runTool(Compositor.screenshotCommand)
                }
                QuickTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    expandable: false
                    icon: "󰊄"
                    title: "OCR"
                    subtitle: "Copy text"
                    onToggled: root.runTool(
                        "grim -t png -g \"$(slurp)\" - | tesseract - - -l eng+deu 2>/dev/null | wl-copy"
                        + " && notify-send -a 'Control center' 'OCR' 'Text copied to clipboard'")
                }
                QuickTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    expandable: false
                    icon: "󰈊"
                    title: "Color"
                    subtitle: "Pick + copy"
                    onToggled: root.runTool(
                        "c=$(hyprpicker -a -f hex) && [ -n \"$c\" ]"
                        + " && notify-send -a 'Control center' 'Color picker' \"$c copied to clipboard\"")
                }
            }

            // ── Batteries (laptop, custom sources, Bluetooth devices) ──
            Flow {
                id: batteries
                Layout.fillWidth: true
                spacing: 8

                readonly property var items: {
                    const out = []
                    const d = UPower.displayDevice
                    if (d?.isLaptopBattery)
                        out.push({ icon: "󰁹", name: "Battery", level: Math.round(d.percentage * 100) })
                    for (const b of CustomBatteries.available)
                        out.push({ icon: b.icon, name: b.name, level: b.level })
                    for (const dev of root.btConnected)
                        if (dev.batteryAvailable)
                            out.push({ icon: "󰂯", name: dev.name, level: Math.round(dev.battery * 100) })
                    return out
                }
                visible: items.length > 0

                Repeater {
                    model: batteries.items
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: chip.implicitWidth + 20
                        implicitHeight: 30
                        radius: 15
                        color: "#27000000"
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.cardBorder

                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: modelData.icon + "  " + modelData.name + "  " + modelData.level + "%"
                            color: modelData.level <= 15 ? "#f38ba8" : modelData.level <= 30 ? "#fab387" : "white"
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                    }
                }
            }

            // ── Volume ──
            AudioCard {
                id: audioCard
                Layout.fillWidth: true
            }

            // ── Notifications ──
            CCCard {
                Layout.fillWidth: true
                implicitHeight: notifs.implicitHeight + 20
                NotificationsSection {
                    id: notifs
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                }
            }
        }
    }
}
