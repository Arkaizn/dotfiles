import Quickshell
import QtQuick 
import qs.services
import qs.components

Item{
    anchors.horizontalCenter: parent.horizontalCenter
    implicitWidth: Properties.buttonWidth + clockRow.implicitWidth
    implicitHeight: Properties.buttonHeight

    property bool hovered: mouseArea.containsMouse

    
    MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: clock.scale = Properties.onEnteredButtonScale
            onExited: clock.scale = Properties.onExitedButtonScale
            cursorShape: Qt.PointingHandCursor
            onClicked: dashboard.toggle()
        }

    // needs to be here because too much text, dont want to pass that through button Background rn ;/
    Behavior on scale {
            NumberAnimation {
                duration: Properties.bDuration
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
            color: Properties.color
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
            color: Properties.color
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            font.letterSpacing: 0.3
        }
    Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.format("ddd d")
                color: Properties.color
                font.pixelSize: 10
                font.weight: Font.Medium
                font.family: "Inter"
            }
    }
}