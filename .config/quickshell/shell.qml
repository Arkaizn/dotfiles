// ~/.config/quickshell/shell.qml
//@ pragma UseQApplication

// =========================================================
// IMPORTS
// =========================================================
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

// =========================================================
// ROOT CONFIGURATION
// =========================================================
ShellRoot {
    property int iconSize: 15
    property int barSpacing: 12
    property int sidePadding: 10

    // =========================================================
    // MULTI-MONITOR SUPPORT
    // =========================================================
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
            // REUSABLE COMPONENT: STAT DISPLAY
            // =========================================================
            Component {
                id: statDisplay

                Rectangle {
                    id: statRoot
                    radius: 8
                    
                    property string icon: ""
                    property string command: ""
                    property int interval: 2000
                    property string suffix: ""
                    property var formatter: null
                    property bool enabled: true
                    property bool trimNewline: true
                    property string displayValue: "…"
                    property bool hovered: false

                    width: statLabel.implicitWidth + 28
                    height: statLabel.implicitHeight + 8

                    // Outer "glass edge" gradient
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: statRoot.hovered
                                ? Qt.rgba(1, 1, 1, 0.45)
                                : Qt.rgba(1, 1, 1, 0.25)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(1, 1, 1, 0.15)
                        }
                    }

                    // Inner "glass body"
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 7
                        color: Qt.rgba(0.12, 0.12, 0.12,
                                    statRoot.hovered ? 0.30 : 0.18)

                        Text {
                            id: statLabel
                            anchors.centerIn: parent
                            font.pixelSize: bar.iconSize
                            color: statRoot.hovered ? Colors.color4 : Colors.color6
                            opacity: statRoot.hovered ? 1.0 : 0.7
                            text: {
                                if (statRoot.displayValue === "…") {
                                    return statRoot.icon.length > 0 ? statRoot.icon + " …" : "…"
                                } else if (statRoot.displayValue.length === 0) {
                                    return statRoot.icon
                                } else if (statRoot.icon.length > 0) {
                                    return statRoot.icon + " " + statRoot.displayValue
                                } else {
                                    return statRoot.displayValue
                                }
                            }
                        }
                    }

                    // Hover detection
                    MouseArea {
                        id: statMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: {
                            statRoot.hovered = true
                            statRoot.scale = 1.08
                        }
                        onExited: {
                            statRoot.hovered = false
                            statRoot.scale = 1.0
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Command execution
                    Process {
                        id: statProc
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (!statRoot.enabled)
                                    return

                                var raw = this.text
                                if (statRoot.trimNewline)
                                    raw = raw.trim()

                                var value = ""
                                if (statRoot.formatter) {
                                    value = statRoot.formatter(raw)
                                } else {
                                    value = raw.length > 0 ? raw + statRoot.suffix : ""
                                }

                                statRoot.displayValue = value
                            }
                        }
                    }

                    // Periodic updates
                    Timer {
                        interval: statRoot.interval
                        running: statRoot.enabled && statRoot.command.length > 0
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            if (statRoot.enabled && statRoot.command.length > 0) {
                                statProc.exec(["bash", "-lc", statRoot.command])
                            }
                        }
                    }
                }
            }

            // =========================================================
            // REUSABLE COMPONENT: CLICKABLE ICON
            // =========================================================
            Component {
                id: clickIcon

                Rectangle {
                    id: iconRoot
                    radius: 8

                    property string glyph: "?"
                    property var command: []
                    property bool hovered: false

                    width: iconText.implicitWidth + 14
                    height: iconText.implicitHeight + 8

                    // Outer "glass edge" gradient
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: iconRoot.hovered
                                ? Qt.rgba(1, 1, 1, 0.45)
                                : Qt.rgba(1, 1, 1, 0.25)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(1, 1, 1, 0.15)
                        }
                    }

                    // Inner "glass body"
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 7
                        color: Qt.rgba(0.12, 0.12, 0.12,
                                    iconRoot.hovered ? 0.30 : 0.18)

                        Text {
                            id: iconText
                            anchors.centerIn: parent
                            text: iconRoot.glyph
                            font.pixelSize: bar.iconSize
                            color: iconRoot.hovered ? Colors.color4 : Colors.color6
                            opacity: iconRoot.hovered ? 1.0 : 0.7
                        }
                    }

                    // Click handling
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            iconRoot.hovered = true
                            iconRoot.scale = 1.08
                        }
                        onExited: {
                            iconRoot.hovered = false
                            iconRoot.scale = 1.0
                        }
                        onClicked: {
                            if (iconRoot.command && iconRoot.command.length > 0) {
                                Quickshell.execDetached(iconRoot.command)
                            }
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            // =========================================================
            // BACKGROUND STYLING
            // =========================================================
            Rectangle {
                id: mainShape
                anchors.fill: parent
                radius: 12

                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.color2 }
                    GradientStop { position: 1.0; color: Colors.color1 }
                    orientation: Gradient.Vertical
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: '#cb000000'
                radius: 10
            }

            // =========================================================
            // LEFT SECTION
            // =========================================================
            RowLayout {
                id: leftRow
                anchors.left: parent.left
                anchors.leftMargin: sidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

                // Notification center button
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = "󰣇"
                        item.command = ["bash","-lc","swaync"]
                    }
                }

                // System clock
                Rectangle {
                    id: clockRoot
                    radius: 8
                    Layout.alignment: Qt.AlignVCenter

                    property bool hovered: clockMouseArea.containsMouse

                    width: clockLabel.implicitWidth + 14
                    height: clockLabel.implicitHeight + 8

                    // Outer "glass edge" gradient
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: clockRoot.hovered
                                ? Qt.rgba(1, 1, 1, 0.45)
                                : Qt.rgba(1, 1, 1, 0.25)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(1, 1, 1, 0.15)
                        }
                    }

                    // Inner "glass body"
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 7
                        color: Qt.rgba(0.12, 0.12, 0.12,
                                    clockRoot.hovered ? 0.30 : 0.18)

                        SystemClock { 
                            id: sysClock
                            precision: SystemClock.Seconds
                        }

                        Text {
                            id: clockLabel
                            anchors.centerIn: parent
                            font.pixelSize: bar.iconSize
                            color: clockRoot.hovered ? Colors.color4 : Colors.color6
                            opacity: clockRoot.hovered ? 1.0 : 0.7
                            text: Qt.formatDateTime(sysClock.date, "dd.MM.yyyy hh:mm:ss")
                        }
                    }

                    // Hover detection
                    MouseArea {
                        id: clockMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: clockRoot.scale = 1.08
                        onExited: clockRoot.scale = 1.0
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Package updates indicator
                Loader {
                    id: pacman
                    sourceComponent: statDisplay
                    Layout.alignment: Qt.AlignVCenter
                    onLoaded: {
                        item.icon = "󰅢 "
                        item.interval = 10000
                        item.command = "checkupdates | wc -l"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash","-lc","kitty --class custom_hover -e yay -Syu --noconfirm"])
                    }
                }

                // Dotfiles git pull button
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = " 󰇚 "
                        item.command = ["bash","-lc","kitty --class custom_hover -e bash ~/git/dotfiles/scripts/config/update.sh "]
                    }
                }

                // Dotfiles git push button
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = " 󰕒 "
                        item.command = ["bash","-lc","kitty --class custom_hover -e bash ~/git/dotfiles/scripts/config/push.sh"]
                    }
                }

                // System tray
                RowLayout {
                    id: systemTrayRow
                    spacing: 4

                    Repeater {
                        model: SystemTray.items

                        delegate: Rectangle {
                            id: trayButton
                            radius: 8

                            width: bar.iconSize + 14
                            height: bar.iconSize + 8

                            property bool hovered: ma.containsMouse

                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: trayButton.hovered
                                        ? Qt.rgba(1, 1, 1, 0.45)
                                        : Qt.rgba(1, 1, 1, 0.25)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 7
                                color: Qt.rgba(0.12, 0.12, 0.12,
                                            trayButton.hovered ? 0.30 : 0.18)

                                IconImage {
                                    anchors.centerIn: parent
                                    width: bar.iconSize
                                    height: bar.iconSize
                                    source: modelData.icon
                                }
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                onEntered: trayButton.scale = 1.08
                                onExited: trayButton.scale = 1.0

                                onClicked: function(mouse) {
                                    // Right click: show context menu
                                    if (mouse.button === Qt.RightButton) {
                                        if (modelData.hasMenu || modelData.onlyMenu) {
                                            // Calculate position relative to the bar window
                                            var globalPos = trayButton.mapToItem(bar.contentItem, 0, 0)
                                            modelData.display(
                                                bar,
                                                globalPos.x,
                                                globalPos.y + trayButton.height + 4
                                            )
                                        }
                                        return
                                    }

                                    // Middle click: secondary action
                                    if (mouse.button === Qt.MiddleButton) {
                                        if (modelData.secondaryActivate)
                                            modelData.secondaryActivate()
                                        return
                                    }

                                    // Left click: activate or show menu
                                    if (modelData.onlyMenu && modelData.hasMenu) {
                                        var globalPos = trayButton.mapToItem(bar.contentItem, 0, 0)
                                        modelData.display(
                                            bar,
                                            globalPos.x,
                                            globalPos.y + trayButton.height + 4
                                        )
                                    } else {
                                        modelData.activate()
                                    }
                                }

                                onWheel: function(wheel) {
                                    if (modelData.scroll)
                                        modelData.scroll(wheel.angleDelta.y, false)
                                }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }

            // =========================================================
            // CENTER SECTION
            // =========================================================
            RowLayout {
                id: centerRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

                // GPU usage
                Loader {
                    sourceComponent: statDisplay
                    onLoaded: {
                        item.icon = "󰢮 "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"
                    }
                }

                // CPU usage
                Loader {
                    sourceComponent: statDisplay
                    onLoaded: {
                        item.icon = " "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "top -bn1 | grep \"Cpu(s)\" | awk '{print 100 - $8}' | cut -d. -f1"
                    }
                }

                // RAM usage
                Loader {
                    sourceComponent: statDisplay
                    onLoaded: {
                        item.icon = " "
                        item.interval = 2000
                        item.suffix = "%"
                        item.command = "free -h | awk '/Mem:/ {print int($3/$2*100)}'"
                    }
                }

                // Separator
                Text {
                    text: "|"
                    font.pixelSize: bar.iconSize
                    color: Colors.foreground
                    opacity: 0.6
                }

                // Hyprland workspaces
                Row {
                    spacing: 6
                    Repeater {
                        model: Hyprland.workspaces

                        Rectangle {
                            required property HyprlandWorkspace modelData

                            radius: 8
                            width: label.implicitWidth + 14
                            height: label.implicitHeight + 8

                            property bool hovered: workspaceMouse.containsMouse

                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: modelData.active
                                        ? Qt.rgba(1, 1, 1, 0.45)
                                        : Qt.rgba(1, 1, 1, 0.25)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 7
                                color: Qt.rgba(0.12, 0.12, 0.12,
                                            modelData.active ? 0.30 : 0.18)

                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    font.pixelSize: bar.iconSize
                                    text: modelData.name
                                    color: modelData.active
                                        ? Colors.color4
                                        : Colors.color6
                                    opacity: modelData.active ? 1.0 : 0.5
                                }
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.activate()

                                onEntered: parent.scale = 1.08
                                onExited: parent.scale = 1.0
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }

                // Separator
                Text {
                    text: "|"
                    font.pixelSize: bar.iconSize
                    color: Colors.foreground
                    opacity: 0.6
                }

                // GPU temperature
                Loader {
                    sourceComponent: statDisplay
                    onLoaded: {
                        item.icon = "󰢮 "
                        item.interval = 5000
                        item.suffix = "°C"
                        item.command = "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader"
                    }
                }

                // CPU temperature
                Loader {
                    sourceComponent: statDisplay
                    onLoaded: {
                        item.icon = " "
                        item.interval = 5000
                        item.suffix = "°C"
                        item.command = "sensors | grep 'Tctl' | awk '{print $2}' | sed 's/+//' | cut -d. -f1"
                    }
                }
            }

            // =========================================================
            // RIGHT SECTION
            // =========================================================
            RowLayout {
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: sidePadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: barSpacing

                // Headset battery
                Loader {
                    sourceComponent: statDisplay
                    Layout.alignment: Qt.AlignVCenter
                    onLoaded: {
                        item.icon = "  󰁹"
                        item.enabled = true
                        item.interval = 5000
                        item.suffix = "%"
                        item.command = "curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"
                    }
                }

                // Bluetooth status
                Loader {
                    id: bluetoothLoader
                    sourceComponent: statDisplay
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
                                item.icon = "󰂱"
                            } else if (state === "idle") {
                                item.icon = "󰂯"
                            } else if (state === "off") {
                                item.icon = "󰂲"
                            } else {
                                item.icon = "󰂲"
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
                    sourceComponent: statDisplay
                    Layout.alignment: Qt.AlignVCenter
                    onLoaded: {
                        item.icon = "󰕾"
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

                // Network status
                Loader {
                    id: networkLoader
                    sourceComponent: statDisplay
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
                                item.icon = "󰌗"
                            } else if (wifiUp) {
                                item.icon = "󰤨"
                            } else {
                                item.icon = "󰤭"
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
                    sourceComponent: statDisplay
                    Layout.alignment: Qt.AlignVCenter
                    
                    // Check if upower actually lists a battery device
                    visible: {
                        try {
                            var res = Quickshell.exec(["sh", "-c", "upower -e | grep -q battery && echo 'yes'"]);
                            return res.out.includes("yes");
                        } catch (e) {
                            return false;
                        }
                    }

                    onLoaded: {
                        if (item) {
                            item.icon = "󰁹"
                            item.interval = 60000
                            // Find the battery dynamically so it works on any machine
                            item.command = "upower -i $(upower -e | grep battery | head -n1) | awk '/percentage:/ {print $2}'"
                        }
                    }
}

                // Logout/power menu
                Loader {
                    sourceComponent: clickIcon
                    onLoaded: {
                        item.glyph = "⏻ "
                        item.command = ["bash","-lc","wlogout"]
                    }
                }
            }
        }
    }
}