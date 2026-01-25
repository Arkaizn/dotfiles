import Quickshell
import QtQuick 

import "../../.."

Rectangle{
    id: root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    
    // color: Qt.rgba(0.12, 0.12, 0.12,root.hovered ? 0.30 : 0.18)

    property bool hovered: mouseArea.containsMouse

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.25)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(1, 1, 1, 0.15)
        }
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
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    
    SystemClock { 
        id: sysClock
        precision: SystemClock.Seconds
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)
        Text {
            id: text
            anchors.centerIn: parent
            font.pixelSize: bar.pixelSize
            color: root.hovered ? Colors.color4 : Colors.color6
            opacity: root.hovered ? 1.0 : 0.7
            text: Qt.formatDateTime(sysClock.date, "dd.MM.yyyy hh:mm:ss")
        }
    }
}