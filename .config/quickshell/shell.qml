// ~/.config/quickshell/shell.qml

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Colors.qml"

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }

    height: 45
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

    // =========================================================
    // REUSABLE HELPERS
    // =========================================================

    // Reusable component that runs a shell command periodically and displays its output.
    Component {
        id: commandLabel

        Item {
            id: root

            property string icon: ""
            property string command: ""
            property int interval: 2000
            property string suffix: ""
            property var formatter: null
            property bool enabled: true
            property bool trimNewline: true
            property int fontSize: bar.iconSize

            implicitWidth: label.implicitWidth
            implicitHeight: label.implicitHeight

            Text {
                id: label
                font.pixelSize: root.fontSize
                color: Colors.foreground
                text: root.icon.length > 0 ? root.icon + " …" : "…"
            }

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

    // Clickable icon that executes a detached command
    Component {
        id: clickIcon

        Item {
            id: iconRoot
            property string glyph: "?"
            property var command: []

            implicitWidth: iconText.implicitWidth
            implicitHeight: iconText.implicitHeight

            Text {
                id: iconText
                text: glyph
                font.pixelSize: bar.iconSize
                color: Colors.foreground
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (iconRoot.command && iconRoot.command.length > 0) {
                        Quickshell.execDetached(iconRoot.command)
                    }
                }
            }
        }
    }

    // =========================================================
    // BACKGROUND
    // =========================================================
    Rectangle {
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
    RowLayout {
        anchors.fill: parent
        anchors.margins: sidePadding
        spacing: barSpacing

        // ================= LEFT =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            spacing: 10

            // Notifications

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
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="󰅢  "; item.interval=600000; item.command="checkupdates 2>/dev/null | wc -l" } }

            // Dotfiles pull/push
            Loader { sourceComponent: clickIcon; onLoaded: { item.glyph="󰇚 "; item.command=["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/update.sh"] } }
            Loader { sourceComponent: clickIcon; onLoaded: { item.glyph="󰕒 "; item.command=["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/push.sh"] } }
        }

        Item { Layout.fillWidth: true }

        // ================= CENTER =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            spacing: 12

            // left side center
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="󰢮  "; item.interval=2000; item.suffix="%"; item.command="nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits" } }
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="  "; item.interval=2000; item.suffix="%"; item.command="top -bn1 | grep \"Cpu(s)\" | awk '{print 100 - $8}' | cut -d. -f1" } }
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="  "; item.interval=2000; item.suffix="%"; item.command="free -h | awk '/Mem:/ {print int($3/$2*100)}'" } }

            Text { text:"|"; font.pixelSize: bar.iconSize; color: Colors.foreground; opacity:0.6 }

            // Hyprland workspaces
            Row {
                spacing: 6
                Repeater {
                    model: Hyprland.workspaces
                    Text {
                        required property HyprlandWorkspace modelData
                        font.pixelSize: bar.iconSize
                        text: ""
                        color: modelData.active ? Colors.color4 : Colors.foreground
                        opacity: modelData.active || modelData.urgent ? 1.0 : 0.5
                        MouseArea { anchors.fill: parent; onClicked: modelData.activate() }
                    }
                }
            }

            // right side center
            Text { text:"|"; font.pixelSize: bar.iconSize; color: Colors.foreground; opacity:0.6 }

            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="󰢮  "; item.interval=5000; item.suffix="°C"; item.command="nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader" } }
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="  "; item.interval=5000; item.command="sensors | grep 'Tctl' | awk '{print $2}' | sed 's/+//'" } }
        }

        Item { Layout.fillWidth: true }
 
        // ================= RIGHT =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 10

            Loader { sourceComponent: commandLabel; onLoaded: { item.icon=""; item.enabled=false; item.interval=5000; item.suffix="%"; item.command="curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'" } }

            // Volume
            Item {
                Layout.alignment: Qt.AlignVCenter
                Loader { id: vol; sourceComponent: commandLabel; onLoaded: { item.icon=""; item.interval=1000; item.suffix="%"; item.command="pamixer --get-volume" } }
                MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"]) }
            }

            Loader { sourceComponent: commandLabel; onLoaded: { item.icon=""; item.interval=5000; item.command="nmcli -t -f DEVICE,STATE d | grep -E ':connected' | cut -d: -f1 | head -n1"; item.formatter=function(raw){var name=raw.trim(); return name===""?"down":name} } }
            Loader { sourceComponent: commandLabel; onLoaded: { item.icon="󰁹"; item.interval=60000; item.command="upower -i $(upower -e | grep BAT | head -n1) | awk '/percentage:/ {print $2}'" } }
            Loader { sourceComponent: clickIcon; onLoaded: { item.glyph=""; item.command=["bash","-lc","wlogout"] } }
        }
    }
}
