import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Effects

PanelWindow {
    id: testing
    visible: false
    anchors {
        top: true
        right: true
    }
    implicitWidth: 400
    implicitHeight: 400
    color: '#00000000'


    BackgroundEffect.blurRegion: Region {
        item: animatedRectangle
        radius: 24
    }

    Rectangle {
        id: animatedRectangle
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        radius: 24
    }
    
}