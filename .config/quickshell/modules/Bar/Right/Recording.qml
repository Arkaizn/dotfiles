import Quickshell
import QtQuick
import qs.services
import qs.components

// Recording indicator (services/Capture.qml): red dot + time while
// wf-recorder runs, the countdown before a delayed screenshot. Click stops the
// recording. Hidden otherwise.
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    visible: Capture.recording || Capture.countdown > 0
    property bool hovered: mouseArea.containsMouse

    readonly property string time: Math.floor(Capture.elapsed / 60) + ":" + String(Capture.elapsed % 60).padStart(2, "0")

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        textColor: Capture.recording ? "#f38ba8" : Properties.color
        iconText: Capture.recording ? (root.hovered ? "󰓛 stop" : "󰑊 " + root.time) : "󰔟 " + Capture.countdown
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
        onClicked: if (Capture.recording) Capture.stop()
    }
}
