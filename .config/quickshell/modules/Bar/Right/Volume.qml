import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs.services
import qs.components

// Left click: control center · right click: mute · wheel: ±5%
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    property bool hovered: mouseArea.containsMouse

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    readonly property string label: {
        if (!audio) return Icons.get("volNone") + " --%"
        const v = isNaN(audio.volume) ? 0 : Math.round(audio.volume * 100)
        if (audio.muted) return Icons.get("volMuted") + " " + v + "%"
        const name = (sink.name + " " + (sink.description ?? "")).toLowerCase()
        // headphones keep their own icon, speakers follow the level
        const icon = name.includes("headset") || name.includes("headphone") ? Icons.get("headphones")
                   : v < 34 ? Icons.get("volLow")
                   : v < 67 ? Icons.get("volMid")
                   : Icons.get("volHigh")
        return icon + " " + v + "%"
    }

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: root.label
        iconSize: 16
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale

        onWheel: wheel => {
            // step and limit: Settings → Audio
            Audio.nudge(root.audio, wheel.angleDelta.y > 0)
        }

        // onClicked (not onPressed) so the press animation plays before the action
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.audio) root.audio.muted = !root.audio.muted
            } else {
                controlCenter.toggle(bar.screen)
            }
        }
    }
}
