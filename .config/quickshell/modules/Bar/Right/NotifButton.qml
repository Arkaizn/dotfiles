import Quickshell
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id: notifBtn
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius

    property bool hovered: notifMouse.containsMouse

    gradient: ButtonGradient { hovered: notifBtn.hovered }

    Behavior on scale {
        NumberAnimation { duration: bar.bDuration; easing.type: Easing.OutCubic }
    }

    ButtonBackground {
        id: buttonBackground
        hovered: notifBtn.hovered
        iconText: "󰂚"
        iconSize: bar.iconSize
    }

    // Optional unread badge
    Rectangle {
        visible: notifCenter.groupModel.count > 0
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
        onEntered: notifBtn.scale = bar.onEnteredButtonScale
        onExited: notifBtn.scale = bar.onExitedButtonScale
        onClicked: notifCenter.toggle()
    }
}