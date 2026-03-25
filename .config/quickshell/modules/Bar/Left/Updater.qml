import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import qs.services

Rectangle {
    id:root
    implicitWidth: text.implicitWidth + bar.buttonWidth
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
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)
        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅢  " + root.output
            font.pixelSize: bar.pixelSize
            color: root.hovered ? Colors.color6 : Colors.foreground
        }
    }

    Process {
        id: process
        command: ["bash", "-lc", "checkupdates | wc -l"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim() 
            }
        }
    }

    Timer {
        interval: 10800000  // Update every 3 hours
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
        onClicked: Quickshell.execDetached(["bash","-lc","kitty --class custom_hover -e bash -c 'sudo ls >/dev/null 2>&1 && sudo pacman -Syu --noconfirm && yay -Quq --aur | xargs -n 1 yay -S --noconfirm'"])
    }
}

