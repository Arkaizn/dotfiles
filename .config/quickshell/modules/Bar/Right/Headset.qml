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
    visible: root.output !== "" || root.output !== null

    property bool hovered: mouseArea.containsMouse
    property string output: ""

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
        iconText: "  󰁹 " + root.output + "%"
        iconSize: bar.pixelSize
    }

    Process {
        id: process
        command: ["bash", "-lc", "curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"]
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
        cursorShape: Qt.PointingHandCursor
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"])    
    }
}

