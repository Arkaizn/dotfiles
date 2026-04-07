import Quickshell
import QtQuick 
import qs.services
import qs.components

Rectangle{
    anchors.horizontalCenter: parent.horizontalCenter
    implicitWidth: bar.buttonWidth + clockRow.implicitWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse

    gradient: ButtonGradient {
        hovered: clock.hovered
    }
    
    MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: clock.scale = onEnteredButtonScale
            onExited: clock.scale = onExitedButtonScale
        }

    Behavior on scale {
            NumberAnimation {
                duration: bar.bDuration
                easing.type: Easing.OutCubic
            }
        }

    ButtonBackground {
    id: buttonBackground
    }

    Row {
        id: clockRow
        anchors.centerIn: parent 
        spacing: 1
        anchors.verticalCenter: parent.verticalCenter
        
        Text {
            id: hoursText
            text: Time.format("hh")
            color: Colors.foreground
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            font.letterSpacing: 0.3
        }

        Text {
            id: colonSeparator
            text: ":"
            color: Colors.color4
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            
            // Subtle pulse animation
            SequentialAnimation on opacity {
                running: true
                loops: Animation.Infinite
                
                NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Text { 
            id: minutesText
            text: Time.format("mm")
            color: Colors.foreground
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            font.letterSpacing: 0.3
        }
    Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.format("ddd d")
                color: Colors.foreground
                font.pixelSize: 10
                font.weight: Font.Medium
                font.family: "Inter"
            }
    }
}