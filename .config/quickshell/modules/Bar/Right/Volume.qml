import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

import "../../.."

Rectangle {
    id:root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse
    property int output: 0

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
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)
        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "󰕾 " + root.output + "%"
            font.pixelSize: bar.pixelSize
            color: root.hovered ? Colors.color4 : Colors.color6
        }
    }

    Process {
        id: process
        command: ["bash", "-lc", "pamixer --get-volume"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim() 
            }
        }
        onRunningChanged: if (!running) running = true
    }

    Timer {
        interval: 5000
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
        onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"])
    }
}

