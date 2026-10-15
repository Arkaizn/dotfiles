import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1
    radius: Properties.buttonradius

    property bool hovered: mouseArea.containsMouse
    property int output: 0

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: Properties.bDuration
            easing.type: Easing.OutCubic
        } 
    }
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "󰢮  " + root.output + "°"
        iconSize: Properties.pixelSize
    }

    Process {
        id: process
        command: ["bash", "-lc", "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim() 
            }
        }
    }

    Timer {
        interval: Properties.interval 
        running: true
        repeat: true
        onTriggered: process.running = true  // Rerun process
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onEntered: root.scale = Properties.onEnteredButtonScale
        onExited: root.scale = Properties.onExitedButtonScale
        onPressed: root.scale = Properties.onPressedButtonScale
        onReleased: root.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: root.scale = Properties.onExitedButtonScale
    }
}

