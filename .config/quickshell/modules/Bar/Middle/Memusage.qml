import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id:root
    implicitWidth: text.implicitWidth + Properties.buttonWidth
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
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)
        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "  " + root.output + "%"
            font.pixelSize: Properties.pixelSize
            color: root.hovered ? Colors.color6 : Colors.foreground
        }
    }

    Process {
        id: process
        command: ["bash", "-lc", "free -h | awk '/Mem:/ {print int($3/$2*100)}'"]
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

