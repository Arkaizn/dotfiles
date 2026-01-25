import Quickshell
import QtQuick
import QtQuick.Controls

import "../../.."

Rectangle {
    id:archIcon
    implicitWidth: archIcontext.implicitWidth + 10
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: archIconMouseArea.containsMouse

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: archIcon.hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.25)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        } 
    }
    
    Text {
        id: archIcontext
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        text: "󰣇"
        font.pixelSize: bar.pixelSize
        color: archIcon.hovered ? Colors.color4 : Colors.color6
    }

    MouseArea {
        id: archIconMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onEntered: archIcon.scale = bar.onEnteredButtonScale
        onExited: archIcon.scale = onExitedButtonScale
        onClicked: Quickshell.execDetached(["swaync-client", "-t", "-sw"])
    }
}