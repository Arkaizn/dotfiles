// ~/.config/quickshell/shell.qml
//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.DBusMenu
import Quickshell.Widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

import "Colors.qml"

ShellRoot {
    // Global defaults
    property int iconSize: 15
    property int barSpacing: 12
    property int sidePadding: 10

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar

            property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

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

            Component.onCompleted: Quickshell.inhibitReloadPopup()

            // =========================================================
            // REUSABLE HELPERS
            // =========================================================

            // Command-driven pill
            Component {
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

            // Clickable icon pill
            Component {
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
                        cursorShape: Qt.PointingHandCursor
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


            Shape {
                id: mainShape
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    id: myPath
                    strokeWidth: 0
                    strokeColor: "transparent"

                    // Force the gradient to use the absolute bounds of the Shape
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0
                        x2: mainShape.width; y2: mainShape.height
                        
                        GradientStop { position: 0.0; color: Colors.color1 }
                        GradientStop { position: 1.0; color: Colors.color2 }
                    }

                    // Rounded Rectangle Path
                    startX: 12; startY: 0
                    PathLine { x: mainShape.width - 12; y: 0 }
                    PathArc  { x: mainShape.width; y: 12; radiusX: 12; radiusY: 12 }
                    PathLine { x: mainShape.width; y: mainShape.height - 12 }
                    PathArc  { x: mainShape.width - 12; y: mainShape.height; radiusX: 12; radiusY: 12 }
                    PathLine { x: 12; y: mainShape.height }
                    PathArc  { x: 0; y: mainShape.height - 12; radiusX: 12; radiusY: 12 }
                    PathLine { x: 0; y: 12 }
                    PathArc  { x: 12; y: 0; radiusX: 12; radiusY: 12 }
                }
            }


            // The "Black Box" that sits inside to create the border look
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2 // This is your border thickness
                color: "black"
                radius: 11 // Slightly smaller radius to align with outer curve
            }

            // =========================================================
            // LEFT BLOCK
            // =========================================================

            RowLayout {
                id: leftRow
                anchors.left: parent.left
                anchors.leftMargin: sidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

                // Notifications
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
                    id: pacman
                    sourceComponent: commandLabel
                    Layout.alignment: Qt.AlignVCenter
                    onLoaded: {
                        item.icon = "󰅢   "
                        item.interval = 10000
                        item.command = "checkupdates | wc -l"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash","-lc","kitty -e yay -Syu --noconfirm"])
                    }
                }

                // Dotfiles pull
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = "󰇚"
                        item.command = ["bash","-lc","kitty --class custom_hover -e bash ~/git/dotfiles/scripts/config/update.sh "]
                    }
                }

                // Dotfiles push
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = "󰕒"
                        item.command = ["bash","-lc","kitty --class custom_hover -e bash ~/git/dotfiles/scripts/config/push.sh"]
                    }
                }

                // System Tray
                RowLayout {
                    id: systemTrayRow
                    spacing: 4

                    Repeater {
                        model: SystemTray.items

                        delegate: Rectangle {
                            id: trayButton
                            radius: 8
                            color: ma.containsMouse ? Colors.color1 : "transparent"

                            implicitWidth: bar.iconSize + 8
                            implicitHeight: bar.iconSize + 8

                            IconImage {
                                anchors.centerIn: parent
                                width: bar.iconSize
                                height: bar.iconSize
                                source: modelData.icon
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        if (modelData.hasMenu || modelData.onlyMenu) {
                                            modelData.display(bar,
                                                trayButton.x,
                                                trayButton.y + trayButton.height)
                                        }
                                        return
                                    }

                                    if (mouse.button === Qt.MiddleButton) {
                                        if (modelData.secondaryActivate)
                                            modelData.secondaryActivate()
                                        return
                                    }

                                    if (modelData.onlyMenu && modelData.hasMenu) {
                                        modelData.display(bar,
                                            trayButton.x,
                                            trayButton.y + trayButton.height)
                                    } else {
                                        modelData.activate()
                                    }
                                }

                                onWheel: function(wheel) {
                                    if (modelData.scroll)
                                        modelData.scroll(wheel.angleDelta.y, false)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            states: State {
                                name: "hover"
                                when: ma.containsMouse
                                PropertyChanges { target: trayButton; scale: 1.04 }
                            }
                        }
                    }
                }
            }

            // =========================================================
            // CENTER BLOCK (fixed true center)
            // =========================================================

            RowLayout {
                id: centerRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

                // GPU usage
                Loader {
                    sourceComponent: commandLabel
                    onLoaded: {
                        item.icon = "󰢮 "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"
                    }
                }

                // CPU usage
                Loader {
                    sourceComponent: commandLabel
                    onLoaded: {
                        item.icon = " "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "top -bn1 | grep \"Cpu(s)\" | awk '{print 100 - $8}' | cut -d. -f1"
                    }
                }

                // RAM usage
                Loader {
                    sourceComponent: commandLabel
                    onLoaded: {
                        item.icon = "  "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "free -h | awk '/Mem:/ {print int($3/$2*100)}'"
                    }
                }

                Text {
                    text: "|"
                    font.pixelSize: bar.iconSize
                    color: Colors.foreground
                    opacity: 0.6
                }

                // Workspaces
                Row {
                    spacing: 6
                    Repeater {
                        model: Hyprland.workspaces

                        Text {
                            required property HyprlandWorkspace modelData
                            font.pixelSize: bar.iconSize
                            text: ""
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

                Text {
                    text: "|"
                    font.pixelSize: bar.iconSize
                    color: Colors.foreground
                    opacity: 0.6
                }

                // GPU temp
                Loader {
                    sourceComponent: commandLabel
                    onLoaded: {
                        item.icon = "󰢮 "
                        item.interval = 5000
                        item.suffix = "°C"
                        item.command = "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader"
                    }
                }

                // CPU temp
                Loader {
                    sourceComponent: commandLabel
                    onLoaded: {
                        item.icon = " "
                        item.interval = 5000
                        item.command = "sensors | grep 'Tctl' | awk '{print $2}' | sed 's/+//'"
                    }
                }
            }

            // =========================================================
            // RIGHT BLOCK
            // =========================================================

            RowLayout {
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: sidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

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

                // Bluetooth
                Loader {
                    id: bluetoothLoader
                    sourceComponent: commandLabel
                    Layout.alignment: Qt.AlignVCenter

                    onLoaded: {
                        item.interval = 5000
                        item.command =
                            "bash -lc '" +
                            "if ! command -v bluetoothctl >/dev/null 2>&1; then echo noadapter; exit; fi; " +
                            "if ! bluetoothctl show | grep -q \"^Controller \"; then echo noadapter; exit; fi; " +
                            "if bluetoothctl show | grep -q \"Powered: no\"; then echo off; exit; fi; " +
                            "if bluetoothctl devices Connected | grep -q .; then echo connected; else echo idle; fi" +
                            "'"

                        item.formatter = function (raw) {
                            var state = raw.trim()
                            bluetoothLoader.visible = (state !== "noadapter")

                            if (state === "connected") {
                                item.icon = "󰂱 "
                            } else if (state === "idle") {
                                item.icon = "󰂯 "
                            } else if (state === "off") {
                                item.icon = "󰂲 "
                            } else {
                                item.icon = "󰂲 "
                            }
                            return ""
                        }
                    }

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
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"])
                    }
                }

                // Network
                Loader {
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
                                if (parts.length < 4)
                                    continue

                                var iface = parts[1]
                                var type  = parts[2]
                                var state = parts[3]

                                if (iface === "lo" ||
                                    iface.startsWith("br") ||
                                    iface.startsWith("docker") ||
                                    iface.startsWith("tailscale"))
                                    continue

                                if (state === "routable" ||
                                    state === "configured" ||
                                    state === "carrier") {
                                    if (type === "ether")
                                        ethernetUp = true
                                    else if (type === "wlan")
                                        wifiUp = true
                                }
                            }

                            if (ethernetUp) {
                                item.icon = ""
                            } else if (wifiUp) {
                                item.icon = "󰤨 "
                            } else {
                                item.icon = "󰤭 "
                            }

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

                // Laptop battery
                Loader {
                    id: battery
                    sourceComponent: commandLabel
                    Layout.alignment: Qt.AlignVCenter
                    visible: true

                    onLoaded: {
                        var hasBattery = false
                        try {
                            var output = Quickshell.exec([
                                "bash","-lc",
                                "upower -e | grep BAT | head -n1"
                            ])
                            hasBattery = output && output.trim().length > 0
                        } catch (e) {
                            hasBattery = false
                        }

                        item.icon = "󰁹 "
                        item.interval = 60000
                        item.command =
                            "upower -i $(upower -e | grep BAT | head -n1) | awk '/percentage:/ {print $2}'"

                        battery.visible = hasBattery
                    }
                }

                // Wlogout
                Loader {
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
