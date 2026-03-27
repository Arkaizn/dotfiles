import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id:root
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse
    property int output: 0

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    Behavior on scale {
        NumberAnimation {
            duration: bar.bduration
            easing.type: Easing.OutCubic
        } 
    }
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "  " + root.output + "°"
        iconSize: bar.pixelSize
    }

    Process {
        id: process
        command: ["bash", "-lc", "sensors | grep -E '^Package|^Core' | grep -o '+[0-9][0-9]\\.[0-9]°C' | sed 's/+//;s/°C//' | awk '{sum+=$1} END {printf \"%.0f\", sum/NR}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim() 
            }
        }
    }

    Timer {
        interval: bar.interval 
        running: true
        repeat: true
        onTriggered: process.running = true  // Rerun process
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = onExitedButtonScale
    }
}

