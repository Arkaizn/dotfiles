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
    property string icon: "󰂲"

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
        command: ["bash", "-lc", "if ! command -v bluetoothctl >/dev/null 2>&1; then echo noadapter; exit; fi; if ! bluetoothctl show | grep -q '^Controller '; then echo noadapter; exit; fi; if bluetoothctl show | grep -q 'Powered: no'; then echo off; exit; fi; if bluetoothctl devices Connected | grep -q .; then echo connected; else echo idle; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var state = this.text.trim()
                root.visible = (state !== "noadapter")

                if (state === "connected") {
                    root.icon = "󰂱"
                } else if (state === "idle") {
                    root.icon = "󰂯"
                } else if (state === "off") {
                    root.icon = "󰂲"
                } else {
                    root.icon = "󰂲"
                }
            }
        }
        onRunningChanged: if (!running) running = true
    }

    Timer {
        interval: 5000
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
        onClicked: Quickshell.execDetached([
            "bash", "-lc",
            "command -v blueman-manager >/dev/null && blueman-manager || command -v bluetuith >/dev/null && alacritty -e bluetuith || alacritty -e bluetoothctl"
        ])
    }
}
