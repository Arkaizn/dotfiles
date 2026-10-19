import Quickshell
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls
import qs.services
import qs.components

Item {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight


    property bool hovered: mouseArea.containsMouse
    
    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: Icons.get("arch")
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        // no click action for now; hover/press animation only
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: {
            buttonBackground.scale = Properties.onExitedButtonScale
        }
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale
    }
}