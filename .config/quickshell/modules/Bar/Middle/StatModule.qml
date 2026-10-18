import QtQuick
import qs.services
import qs.components

// One number on the bar (CPU / GPU / memory / temperatures), from SysStats.
// Hidden while the value is unknown (-1), e.g. no NVIDIA GPU.
Rectangle {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    radius: Properties.buttonradius
    visible: value >= 0

    property string icon
    property int value: -1
    property string suffix: "%"
    property bool hovered: mouseArea.containsMouse

    Component.onCompleted: SysStats.acquire()
    Component.onDestruction: SysStats.release()

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    Behavior on scale {
        NumberAnimation {
            duration: Properties.bDuration
            easing.type: Easing.OutCubic
        }
    }

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: root.icon + "  " + root.value + root.suffix
        iconSize: Properties.pixelSize
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onEntered: root.scale = Properties.onEnteredButtonScale
        onExited: root.scale = Properties.onExitedButtonScale
        onPressed: root.scale = Properties.onPressedButtonScale
        onReleased: root.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: root.scale = Properties.onExitedButtonScale
    }
}
