import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
        right: true
    }
    implicitWidth: 200
    implicitHeight: 100
    color: "transparent"

    function toggle() {
        BarState.popupOpenRight = !root.visible
        root.visible = !root.visible
    }

    Rectangle {
        id: rect
        anchors.fill: parent
        anchors.rightMargin: 10
        anchors.leftMargin:10
        color: '#45000000'
        bottomLeftRadius: 10
    }

    InverseCorner {
        anchors.right: rect.left
        anchors.top: rect.top
        corner: "topRight"
        color: rect.color
        radius: 12
    }
}