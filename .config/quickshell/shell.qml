// ~/.config/quickshell/shell.qml

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Colors.qml"

ShellRoot {
    // Your properties etc
    property int iconSize: 15
    property int barSpacing: 12
    property int sidePadding: 10

    
    Variants {

        model: Quickshell.screens
        PanelWindow { // Bar
            id: bar
            anchors {
                top: true
                left: true
                right: true
            }

            property var modelData
            screen: modelData
            implicitHeight: 45
            exclusiveZone: height + margins.top
            aboveWindows: true
            focusable: false
            color: "transparent"

            margins.top: 8
            margins.left: 8
            margins.right: 8

            property int iconSize: 15
            property int barSpacing: 12
            property int sidePadding: 10

            Component.onCompleted: {
                Quickshell.inhibitReloadPopup()
            }    

            // =========================================================
            // REUSABLE HELPERS
            // =========================================================

            // Metric / label with hover background (no border)
            Component { // ================ REUSABLE HELPERS =================
                id: commandLabel

                Rectangle {
                    id: root

                    radius: 8
                    color: hovered ? Colors.color1 : "transparent"

                    property bool hovered: false
                    property int paddingX: 6
                    property int paddingY: 4

                    // API
                    property string icon: ""
                    property string command: ""
                    property int interval: 2000
                    property string suffix: ""
                    property var formatter: null
                    property bool enabled: true
                    property bool trimNewline: true
                    property int fontSize: bar.iconSize

                    RowLayout {
                        id: contentRow
                        anchors.fill: parent
                        anchors.leftMargin: paddingX
                        anchors.rightMargin: paddingX
                        anchors.topMargin: paddingY
                        anchors.bottomMargin: paddingY

                        Text {
                            id: label
                            font.pixelSize: root.fontSize
                            color: root.hovered ? Colors.color7 : Colors.foreground
                            text: root.icon.length > 0 ? root.icon + " …" : "…"
                        }
                    }

                    implicitWidth: contentRow.implicitWidth + paddingX * 2
                    implicitHeight: contentRow.implicitHeight + paddingY * 2

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                    }

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Process {
                        id: proc
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (!root.enabled)
                                    return

                                var raw = this.text
                                if (root.trimNewline)
                                    raw = raw.trim()

                                var value = ""
                                if (root.formatter) {
                                    value = root.formatter(raw)
                                } else {
                                    value = raw.length > 0 ? raw + root.suffix : ""
                                }

                                if (value.length === 0) {
                                    label.text = root.icon
                                } else if (root.icon.length > 0) {
                                    label.text = root.icon + " " + value
                                } else {
                                    label.text = value
                                }
                            }
                        }
                    }

                    Timer {
                        id: timer
                        interval: root.interval
                        running: root.enabled && root.command.length > 0
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            if (root.enabled && root.command.length > 0) {
                                proc.exec(["bash", "-lc", root.command])
                            }
                        }
                    }
                }
            }

            Component { // Clickable icon with hover pill (no border)
                id: clickIcon

                Rectangle {
                    id: iconRoot

                    property string glyph: "?"
                    property var command: []
                    property bool hovered: false
                    property int paddingX: 6
                    property int paddingY: 4
        
                    radius: 8
                    color: hovered ? Colors.color1 : "transparent"

                    Text {
                        id: iconText
                        anchors.centerIn: parent
                        text: iconRoot.glyph
                        font.pixelSize: bar.iconSize
                        color: iconRoot.hovered ? Colors.color7 : Colors.foreground
                    }

                    implicitWidth: iconText.implicitWidth + paddingX * 2
                    implicitHeight: iconText.implicitHeight + paddingY * 2

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: iconRoot.hovered = true
                        onExited: iconRoot.hovered = false
                        onClicked: {
                            if (iconRoot.command && iconRoot.command.length > 0) {
                                Quickshell.execDetached(iconRoot.command)
                            }
                        }
                    }

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on scale { NumberAnimation { duration: 80 } }

                    states: State {
                        name: "hover"
                        when: iconRoot.hovered
                        PropertyChanges { target: iconRoot; scale: 1.04 }
                    }
                }
            }

            // =========================================================
            // BACKGROUND
            // =========================================================
            Rectangle { // =============== BACKGROUND ===============
                anchors.fill: parent
                radius: 12
                color: Colors.background
                border.color: Colors.color1
                border.width: 2
                opacity: 0.85
            }

            // =========================================================
            // MAIN LAYOUT
            // =========================================================
            RowLayout { // =============== MAIN LAYOUT ===============
                anchors.fill: parent
                anchors.margins: sidePadding
                spacing: barSpacing

                RowLayout { // ================= LEFT =================
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    spacing: 10
                    Loader {
                        sourceComponent: clickIcon
                        onLoaded: {
                            item.glyph = "󰣇"
                            item.command = ["bash","-lc","swaync"]
                        }
                    }

                    // Clock
                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignVCenter
                        SystemClock { id: sysClock; precision: SystemClock.Seconds }
                        Text {
                            font.pixelSize: bar.iconSize
                            color: Colors.foreground
                            text: Qt.formatDateTime(sysClock.date, "dd.MM.yyyy hh:mm:ss")
                        }
                    }

                    // Pacman updates
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = "󰅢  "
                            item.interval = 600000
                            item.command = "checkupdates 2>/dev/null | wc -l"
                        }
                    }

                    // Dotfiles pull/push
                    Loader {
                        sourceComponent: clickIcon
                        onLoaded: {
                            item.glyph = "󰇚"
                            item.command = ["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/update.sh"]
                        }
                    }
                    Loader {
                        sourceComponent: clickIcon
                        onLoaded: {
                            item.glyph = "󰕒"
                            item.command = ["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/push.sh"]
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                
                RowLayout { // ================= CENTER =================
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter

                    // left side center
                    // GPU Usage
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = "󰢮 "
                            item.interval = 2000
                            item.suffix = "%"
                            item.command = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"
                        }
                    }
                    // CPU Usage
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = " "
                            item.interval = 2000
                            item.suffix = "%"
                            item.command = "top -bn1 | grep \"Cpu(s)\" | awk '{print 100 - $8}' | cut -d. -f1"
                        }
                    }
                    // RAM Usage
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = "  "
                            item.interval = 2000
                            item.suffix = "%"
                            item.command = "free -h | awk '/Mem:/ {print int($3/$2*100)}'"
                        }
                    }

                    // pipe
                    Text { text: "|"; font.pixelSize: bar.iconSize; color: Colors.foreground; opacity: 0.6 }

                    // Hyprland workspaces — no hover effect, only active highlight
                    Row {
                        spacing: 6
                        Repeater {
                            model: Hyprland.workspaces

                            Text {
                                required property HyprlandWorkspace modelData

                                font.pixelSize: bar.iconSize
                                text: ""

                                // Active workspace: bright; inactive: dimmed
                                color: modelData.active ? Colors.color4 : Colors.foreground
                                opacity: modelData.active ? 1.0 : 0.35

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.activate()
                                }
                            }
                        }
                    }

                    // pipe
                    Text { text: "|"; font.pixelSize: bar.iconSize; color: Colors.foreground; opacity: 0.6 }

                    // right side center
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = "󰢮 "
                            item.interval = 5000
                            item.suffix = "°C"
                            item.command = "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader"
                        }
                    }
                    Loader {
                        sourceComponent: commandLabel
                        onLoaded: {
                            item.icon = " "
                            item.interval = 5000
                            item.command = "sensors | grep 'Tctl' | awk '{print $2}' | sed 's/+//'"
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                
                RowLayout { // ================= RIGHT =================
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

                    // Headset battery
                    Loader {
                        sourceComponent: commandLabel
                        Layout.alignment: Qt.AlignVCenter

                        onLoaded: {
                            item.icon = " "
                            item.enabled = true
                            item.interval = 5000
                            item.suffix = "%"
                            item.command = "curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"
                        }
                    }



                    
                    Loader {
                        id: bluetoothLoader
                        sourceComponent: commandLabel
                        Layout.alignment: Qt.AlignVCenter

                        onLoaded: {
                            item.interval = 5000
                            // Emit a single state word we can parse reliably.
                            item.command = `
                    bash -lc '
                    if ! command -v bluetoothctl >/dev/null 2>&1; then echo noadapter; exit; fi
                    # Need a controller present
                    if ! bluetoothctl show | grep -q "^Controller "; then echo noadapter; exit; fi
                    # Powered?
                    if bluetoothctl show | grep -q "Powered: no"; then echo off; exit; fi
                    # Any connected devices?
                    if bluetoothctl devices Connected | grep -q .; then echo connected; else echo idle; fi
                    '`.trim()

                            item.formatter = function (raw) {
                                var state = raw.trim()
                                // Optional: hide the icon entirely if there is no adapter.
                                bluetoothLoader.visible = (state !== "noadapter")

                                if (state === "connected") {
                                    item.icon = "󰂱 "   // BT connected
                                    // item.opacity = 1.0
                                } else if (state === "idle") {
                                    item.icon = "󰂯 "   // BT on, no device
                                    // item.opacity = 0.9
                                } else if (state === "off") {
                                    item.icon = "󰂲 "   // BT off
                                    // item.opacity = 0.5
                                } else { // noadapter or anything unexpected
                                    item.icon = "󰂲 "
                                    // item.opacity = 0.0 // or keep it visible but dim
                                }
                                return "" // icon-only, no text
                            }
                        }

                        // Click to open a manager (tries blueman, falls back gracefully)
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([
                                "bash","-lc",
                                "command -v blueman-manager >/dev/null && blueman-manager || " +
                                "command -v bluetuith >/dev/null && alacritty -e bluetuith || " +
                                "alacritty -e bluetoothctl"
                            ])
                        }
                    }


                    // Volume
                    Loader {
                        id: vol
                        sourceComponent: commandLabel
                        Layout.alignment: Qt.AlignVCenter
                        onLoaded: {
                            item.icon = "  "
                            item.interval = 1000
                            item.suffix = "%"
                            item.command = "pamixer --get-volume"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"])
                        }
                    }
                    
                    Loader { // Network
                        id: networkLoader
                        sourceComponent: commandLabel
                        Layout.alignment: Qt.AlignVCenter

                        onLoaded: {
                            item.interval = 4000
                            item.command = "networkctl list --no-pager --no-legend"

                            item.formatter = function(raw) {
                                var lines = raw.trim().split("\n")
                                var ethernetUp = false
                                var wifiUp = false

                                for (var i = 0; i < lines.length; i++) {
                                    var parts = lines[i].trim().split(/\s+/)
                                    if (parts.length < 4) continue

                                    var iface = parts[1]   // e.g. eno1
                                    var type  = parts[2]   // e.g. ether / wlan
                                    var state = parts[3]   // e.g. routable / carrier / no-carrier

                                    // Ignore loopback / docker / bridges / tailscale
                                    if (iface === "lo" || iface.startsWith("br") || iface.startsWith("docker") || iface.startsWith("tailscale"))
                                        continue

                                    if (state === "routable" || state === "configured" || state === "carrier") {
                                        if (type === "ether") ethernetUp = true
                                        else if (type === "wlan") wifiUp = true
                                    }
                                }

                                if (ethernetUp) {
                                    item.icon = ""   // Ethernet symbol
                                } else if (wifiUp) {
                                    item.icon = "󰤨 "   // Wi-Fi symbol
                                } else {
                                    item.icon = "󰤭 "   // No network
                                }

                                // Don’t return any text after the icon
                                return ""
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["bash", "-lc", "iwgtk"])
                        }
                    }


                    Loader { // battery
                        id: battery
                        sourceComponent: commandLabel
                        Layout.alignment: Qt.AlignVCenter
                        visible: true   // default hidden
                        onLoaded: {
                            var hasBattery = false
                            try {
                                var output = Quickshell.exec(["bash","-lc","upower -e | grep BAT | head -n1"])
                                hasBattery = output && output.trim().length > 0
                            } catch (e) { hasBattery = false }

                            item.icon = "󰁹 "
                            item.interval = 60000
                            item.command = "upower -i $(upower -e | grep BAT | head -n1) | awk '/percentage:/ {print $2}'"
                            battery.visible = hasBattery
                        }
                    }

                    Loader { // Wlogout
                        sourceComponent: clickIcon

                        onLoaded: {
                            item.glyph = "  "
                            item.command = ["bash","-lc","wlogout"]
                        }
                    }
                }
            }
        }
    }
}