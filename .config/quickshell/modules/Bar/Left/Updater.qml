import Quickshell
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components


// Pending updates (click: upgrade). When a reboot is needed (kernel updated)
// it shows that too, in orange; with nothing to update, a click shows the
// reboot notification again (with its Reboot now button).
Item {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1


    visible: Updates.count > 0 || Updates.rebootNeeded

    property bool hovered: mouseArea.containsMouse
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: Updates.count > 0 ? "󰅢 " + Updates.count + (Updates.rebootNeeded ? " 󰜉" : "") : "󰜉 Reboot"
        iconSize: 14
        textColor: Updates.rebootNeeded ? Colors.orange : Properties.color
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Updates.count > 0 ? Updates.upgrade() : Updates.notifyReboot()
    }
}

