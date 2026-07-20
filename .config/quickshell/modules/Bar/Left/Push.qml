import Quickshell
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Item {
    id:root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    property bool hovered: mouseArea.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: "󰕒"
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Quickshell.execDetached(["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/push.sh"])
    }
}