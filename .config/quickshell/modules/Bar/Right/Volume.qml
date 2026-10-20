import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs.services
import qs.components

// Left click: control center · right click: mute · wheel: ±5%
BarButton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    text: {
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
    iconSize: 16

    buttons: Qt.LeftButton | Qt.RightButton
    wheelEnabled: true
    // one step (Settings → Audio) per 120 units = one mouse notch; touchpads
    // and hi-res wheels send smaller deltas, which add up
    property real wheelRest: 0
    onWheel: wheel => {
        const d = wheel.angleDelta.y
        if (d === 0) return                                          // sideways scroll
        if (Math.sign(d) !== Math.sign(wheelRest)) wheelRest = 0     // changed direction
        wheelRest += d
        while (Math.abs(wheelRest) >= 120) {
            Audio.nudge(root.audio, wheelRest > 0)
            wheelRest -= Math.sign(wheelRest) * 120
        }
    }

    // onClicked (not onPressed) so the press animation plays before the action
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (root.audio) root.audio.muted = !root.audio.muted
        } else {
            Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
        }
    }
}
