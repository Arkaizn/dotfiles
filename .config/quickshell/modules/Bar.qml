import Quickshell
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
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
    margins.top: 0
    margins.left: 0
    margins.right: 0

    implicitHeight: 70
    exclusiveZone: height
    color: "transparent"
    aboveWindows: true


    // properties / settings
    property int iconSize: 18
    property int spacing: 5
    property int radius: 8
    property int interval: 500 // interval update components in bar
    property int bDuration: 140

    // Text / Font
    property int pixelSize: 12
    property var fontFamily: "Inter"


    // Margin
    property int barMarginBottom: 13
    property int barMarginTop: 13
    property int barMarginLeft: 10
    property int barMarginRight: 10

    // Scale
    property double onEnteredTextScale: 1.2
    property double onExitedTextScale: 1.0
    property double onEnteredButtonScale: 1.1
    property double onExitedButtonScale: 1.0

    // Button settings
    property int buttonHeight: 32
    property int buttonWidth: 20
    property int buttonradius: 10

    // Colors
    property color colorfg: Qt.rgba(0, 0, 0, 0.54)
    property color colorfgHovered: Qt.rgba(0.12, 0.12, 0.12, 0.1) 
    property color buttonColorIfHovered: root.hovered ? Qt.rgba(0, 0, 0, 0.31) : Qt.rgba(0, 0, 0, 0.3)
    property color textColorIfHovered: root.hovered ? Colors.color6 : Colors.foreground



    // visual Bar Border (in the back)
    Item {
        anchors.fill: parent

        Rectangle {
            id: rectangle
            anchors.fill: parent
            anchors.leftMargin: barMarginLeft
            anchors.rightMargin: barMarginRight
            anchors.topMargin: barMarginTop
            anchors.bottomMargin: barMarginBottom
            radius: 10
             color: '#27000000'
            // gradient: Gradient {
            //     GradientStop { position: 0.0; color: Qt.alpha(Colors.color1, 0.1 )}
            //     GradientStop { position: 1.0; color: Qt.alpha(Colors.color8, 0.1 )}
            // }
        }

        MultiEffect {
            source: rectangle
            anchors.fill: rectangle
            shadowEnabled: true
            shadowColor: '#00000000'     
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowBlur: 0.5 // Higher is softer
            shadowScale: 1 // cause of the sides

        }
    }
    



    // Rectangle {
    //     anchors.fill: parent
    //     anchors.margins: 1
    //     radius: 10

    //     gradient: Gradient {
    //         orientation: Gradient.Vertical
    //         GradientStop { position: 0.0; color: Colors.color1 }
    //         GradientStop { position: 1.0; color: Colors.color8 }
    //     }
    // }

    // visual Bar in front

    // Rectangle {
    //     anchors.fill: parent
    //     anchors.leftMargin: barMarginLeft
    //     anchors.rightMargin: barMarginRight
    //     anchors.topMargin: barMarginTop
    //     anchors.bottomMargin: barMarginBottom
    //     color: '#7b000000'
    //     radius: 10
    
    // }

    // Call Bar Buttons
    Left {}
    Middle {}
    Right {}
}