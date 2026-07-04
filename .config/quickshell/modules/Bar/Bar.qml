import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.services
import "."

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

    implicitHeight: 50
    exclusiveZone: height
    color: "transparent"
    aboveWindows: true

    BackgroundEffect.blurRegion: Region {
        item: rectangle
        topLeftRadius: 10
        topRightRadius: 10
        bottomRightRadius: BarState.popupOpenRight ? 0 : 10
        bottomLeftRadius: BarState.popupOpenLeft ? 0 : 10
    }

    Rectangle {
        id: rectangle
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 0
        anchors.bottomMargin: 0
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