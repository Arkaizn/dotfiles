import Quickshell
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls
import qs.services
import qs.components

Item {
    id: notifBtn
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight

    property bool hovered: notifMouse.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: notifBtn.hovered
        iconText: "󰂚"
    }

    // Optional unread badge
    Rectangle {
        visible: notifCenter.groupCount > 0
        anchors { top: parent.top; right: parent.right; margins: 4 }
        width: 8; height: 8
        radius: 4
        color: "#ff5f5f"
    }

    MouseArea {
        id: notifMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: notifCenter.toggle()
    }
}