import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.components

Rectangle {
    id: root
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse
    property string icon: "󰤭"

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: bar.bDuration
            easing.type: Easing.OutCubic
        } 
    }
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: root.icon
        iconSize: bar.iconSize
    }

    Process {
        id: process
        command: ["networkctl", "list", "--no-pager", "--no-legend"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text.trim()
                var lines = raw.split("\n")
                var ethernetUp = false
                var wifiUp = false

                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].trim().split(/\s+/)
                    if (parts.length < 4)
                        continue

                    var iface = parts[1]
                    var type = parts[2]
                    var state = parts[3]

                    if (iface === "lo" ||
                        iface.startsWith("br") ||
                        iface.startsWith("docker") ||
                        iface.startsWith("vmnet") ||
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
                    root.icon = "󰌗"
                } else if (wifiUp) {
                    root.icon = "󰤨"
                } else {
                    root.icon = "󰤭"
                }
            }
        }
    }

    Timer {
        interval: bar.interval
        running: true
        repeat: true
        onTriggered: process.running = true
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = bar.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash", "-lc", "iwgtk"])
    }
}
