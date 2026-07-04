import Quickshell
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Item {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    property bool hovered: mouseArea.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "⏻"
    }
    

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash","-lc","wlogout"])
    }
}