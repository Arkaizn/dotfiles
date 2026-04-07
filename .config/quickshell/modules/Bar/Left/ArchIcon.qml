import Quickshell
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id:root
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse

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
        iconText: "󰣇"
        iconSize: bar.iconSize
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: root.scale = bar.onEnteredButtonScale
        // onExited: root.scale = bar.onExitedButtonScale
        onClicked: {
            // FoldOutManager.toggle("powermenu", root.screenName, true);
        }
        onExited: {
            root.scale = bar.onExitedButtonScale
            // FoldOutManager.setTriggerHovered("powermenu", root.screenName, false);
            // powerMenu.startTimer();
        }
    }
}