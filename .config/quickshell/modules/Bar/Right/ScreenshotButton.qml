import Quickshell
import QtQuick
import qs.services
import qs.components

// Opens the screenshot / recording menu (modules/capture).
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    property bool hovered: mouseArea.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: Icons.get("screenshot")
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Capture.menuOpen = !Capture.menuOpen
    }
}
