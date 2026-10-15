pragma Singleton
import QtQuick

Rectangle {
    id: root

    // properties / settings
    property int iconSize: 18
    property int spacing: 5
    property int radius: 8
    property int interval: 500 // interval update components in bar
    property int bDuration: 140

    // Button Background
    property bool hovered: false
    property string iconText: ""
    property color color: "white"
    

    // Text / Font
    property int pixelSize: 13
    property string fontFamily: "JetBrainsMono Nerd Font"
    property bool fontBold: false   

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

    // Panels — the bar and every popup attached to it (BarPopup)
    property color panelColor: '#50000000'
    property color panelBorder: Qt.rgba(1, 1, 1, 0.13)
    property real panelBorderWidth: 1
    property int barRadius: 10       // bar corners
    property int popupRadius: 12     // notification popup cards
    property int panelRadius: 30     // big widgets: dashboard, notification center, wallpapers, launcher
    property int flareRadius: 30     // inverted corners where a popup meets the bar
    property int barInset: 12        // gap between screen edge and the bar

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

