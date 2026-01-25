import Quickshell
import Quickshell.Io
import QtQuick
import "../../.."

Rectangle {
    id: root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse
    property string icon: "󰤭"

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.25)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        } 
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, root.hovered ? 0.30 : 0.18)

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: bar.iconSize
            color: root.hovered ? Colors.color4 : Colors.color6
        }
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
        onRunningChanged: if (!running) running = true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: process.running = true
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = bar.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash", "-lc", "iwgtk"])
    }
}
