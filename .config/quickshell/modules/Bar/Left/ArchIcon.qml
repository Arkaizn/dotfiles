import Quickshell
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
            text: "󰣇"
            font.pixelSize: bar.iconSize
            color: root.hovered ? Colors.color6 : Colors.foreground
        }
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
            FoldOutManager.toggle("powermenu", root.screenName, true);
        }
        onExited: {
            FoldOutManager.setTriggerHovered("powermenu", root.screenName, false);
            powerMenu.startTimer();
        }
    }
}