pragma Singleton
import QtQuick

Rectangle {
    id: root

property int iconSize: 18
property int spacing: 5
property int radius: 8
property int interval: 500 // interval update components in bar
property int duration: 140

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
}