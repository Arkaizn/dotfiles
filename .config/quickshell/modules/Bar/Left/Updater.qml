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


    visible: root.output !== 0

    property bool hovered: mouseArea.containsMouse
    property int output: 0
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "󰅢   " + root.output
        iconSize: 14
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
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash","-lc","kitty --class custom_hover -e bash -c 'sudo ls >/dev/null 2>&1 && sudo pacman -Syu --noconfirm && yay -Quq --aur | xargs -n 1 yay -S --noconfirm'"])
    }
}

