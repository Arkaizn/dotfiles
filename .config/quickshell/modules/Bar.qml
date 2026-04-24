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
    margins.top: 10
    margins.left: 0
    margins.right: 0

    implicitHeight: 50
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
    property int pixelSize: 13
    property var fontFamily: "Inter"


    // Margin
    property int barMarginBottom: 0
    property int barMarginTop: 0
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


    Rectangle {
        id: rectangle
        anchors.fill: parent
        anchors.leftMargin: barMarginLeft
        anchors.rightMargin: barMarginRight
        anchors.topMargin: barMarginTop
        anchors.bottomMargin: barMarginBottom
        color: '#50000000'
        topLeftRadius: 10
        topRightRadius: 10
        bottomRightRadius: BarState.popupOpenRight ? 0 : 10
        bottomLeftRadius: BarState.popupOpenLeft ? 0 : 10
        Behavior on bottomRightRadius { NumberAnimation { duration: 140 } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 140 } }
    }



    // Call Bar Buttons
    Left {}
    Middle {}
    Right {}
}