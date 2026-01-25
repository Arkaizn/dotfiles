import Quickshell
import QtQuick 

import "../../.."

Rectangle{
    id: clock
    implicitWidth: clockText.implicitWidth + 10
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    
    color: Qt.rgba(0.12, 0.12, 0.12,clock.hovered ? 0.30 : 0.18)

    property bool hovered: clockMouseArea.containsMouse

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: clock.hovered ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.25)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }
    MouseArea {
            id: clockMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: clock.scale = 1.05
            onExited: clock.scale = onExitedButtonScale
        }
    Behavior on scale {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    
    SystemClock { 
        id: sysClock
        precision: SystemClock.Seconds
    }

    Text {
        id: clockText
        anchors.centerIn: parent
        font.pixelSize: bar.iconSize
        color: clock.hovered ? Colors.color4 : Colors.color6
        opacity: clock.hovered ? 1.0 : 0.7
        text: Qt.formatDateTime(sysClock.date, "dd.MM.yyyy hh:mm:ss")
    }
}