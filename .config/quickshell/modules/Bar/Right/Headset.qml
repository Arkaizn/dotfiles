import Quickshell
import QtQuick
import qs.services
import qs.components

// Headset battery (from CustomBatteries); hidden while the headset is off.
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    readonly property int level: CustomBatteries.levelOf("HS80")
    visible: level >= 0

    property bool hovered: mouseArea.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: Icons.get("headphones") + "  " + Icons.get("batFull") + " " + root.level + "%"
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
        onClicked: controlCenter.toggle(bar.screen)
    }
}
