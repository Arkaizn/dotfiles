import Quickshell
import QtQuick
// import QtQuick.Shapes
// import QtQuick.Controls
import Quickshell.Services.Mpris
import qs.services
import qs.components


Rectangle {
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: bar.spacing
    anchors.right: clock.left  // stuck to the left of clock


    property bool hovered: mouseArea.containsMouse

    gradient: ButtonGradient {
    hovered: music.hovered
    }
    Behavior on scale {
        NumberAnimation {
            duration: bar.bDuration
            easing.type: Easing.OutCubic
        } 
    }
    
    ButtonBackground {
        id: buttonBackground
        hovered: music.hovered
        iconText: "󰣇"
        iconSize: bar.iconSize
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: music.scale = bar.onEnteredButtonScale
        onClicked: {
        }
        onExited: {
            music.scale = bar.onExitedButtonScale
        }
    }
}