import Quickshell
import QtQuick 
import qs.services

Rectangle{
    id: root
    implicitWidth: clockRow.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    
    // color: Qt.rgba(0.12, 0.12, 0.12,root.hovered ? 0.30 : 0.18)

    property bool hovered: mouseArea.containsMouse

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    
    MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.scale = 1.05
            onExited: root.scale = onExitedButtonScale
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
        Row {
            id: clockRow
            anchors.centerIn: parent
            spacing: 8
            
            // Compact time display
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                
                // Hours
                Text {
                    id: hoursText
                    text: Time.format("hh")
                    color: root.hovered ? Colors.color6 : Colors.foreground
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.family: "Inter"
                    font.letterSpacing: 0.3
                }
                
                // Animated colon separator
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
                // minutes
                Text { 
                    id: minutesText
                    text: Time.format("mm")
                    color: root.hovered ? Colors.color6 : Colors.foreground
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.family: "Inter"
                    font.letterSpacing: 0.3
                }
                
            }
            
            
            // Compact date
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.format("ddd d")
                color: root.hovered ? Colors.color6 : Colors.foreground
                font.pixelSize: 10
                font.weight: Font.Medium
                font.family: "Inter"
            }
            
        }
    }
}