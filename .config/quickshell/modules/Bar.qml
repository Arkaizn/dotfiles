import Quickshell
import QtQuick
import qs.services
import "Bar"

PanelWindow {
    id: bar

    // for multiple Moniors
    required property var modelData
    screen: modelData

    // Top Bar
    anchors {
        top: true
        left: true
        right: true
    }
    
    // Space between edge of the screen and Bar
    margins.top: 8
    margins.left: 8
    margins.right: 8

    implicitHeight: 45
    exclusiveZone: height + margins.top
    color: "transparent"
    aboveWindows: true


    // properties / settings
    property int iconSize: 18
    property int pixelSize: 15
    property int spacing: 8
    property double onEnteredButtonScale: 1.1
    property double onExitedButtonScale: 1.0
    property int buttonHeight: 26
    property int buttonWidth: 15
    property int buttonradius: 7
    property color colorfg: Qt.rgba(0.12, 0.12, 0.12, 0.30)
    property color colorfgHovered: Qt.rgba(0.12, 0.12, 0.12, 0.18)
    property int interval: 500
    property int bDuration: 140

    // visual Bar Border (in the back)
    Rectangle {
        anchors.fill: parent
        radius: 12

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Colors.color2 }
            GradientStop { position: 1.0; color: Colors.color1 }
        }
    }

    // visual Bar in front
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: '#eb000000'
        radius: 10
    }

    // MusicPopOut {
    //         id: musicPopOut
    //         popOutHeight: 320
    //         // modelData: root.modelData
    //     }

    // Call Bar Buttons
    Left {}
    Middle {}
    Right {}
}