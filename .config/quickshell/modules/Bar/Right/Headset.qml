import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Item {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1
    visible: root.output !== "" && root.output !== "null"

    property bool hovered: mouseArea.containsMouse
    property string output: ""
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "  󰁹 " + root.output + "%"
    }

    Process {
        id: process
        command: ["bash", "-c", "curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim() 
            }
        }
    }

    Timer {
        interval: 10000 // battery level changes slowly, no need for the 500ms bar rate
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
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash","-lc","pavucontrol"])    
    }
}

