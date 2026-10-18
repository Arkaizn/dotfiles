import Quickshell
import QtQuick
import qs.services
import qs.components

// Power profile (services/Power.qml): click cycles power saver → balanced →
// performance. Hidden without power-profiles-daemon.
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    visible: Power.available.length > 0
    property bool hovered: mouseArea.containsMouse

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: (Power.icons[Power.current] ?? "󰗑") + (root.hovered ? " " + Power.labels[Power.current] : "")
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
        onClicked: Power.cycle()
    }
}
