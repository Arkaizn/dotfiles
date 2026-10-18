import QtQuick
import QtQuick.Window
import Quickshell.Services.Pipewire
import qs.services

// Live level of a Pipewire node (device or app stream), like pavucontrol's
// meters: a thin bar that moves with how loud the sound is right now.
// Only measures while it's on screen (its window open, not collapsed away)
// and not muted (then it fades out). Scaled by the slider's volume, so a
// quieter setting gives a shorter bar. dB scale (-60 … 0 dB), jumps up at once
// and falls back smoothly.
Item {
    id: root

    property var node: null
    property bool muted: false
    property real volume: 1          // the node's volume (0 … 1.5), scales the level
    property color color: Colors.color6

    readonly property bool live: node !== null && !muted && visible && (Window.window?.visible ?? false)

    implicitHeight: 3
    opacity: muted ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 180 } }

    PwNodePeakMonitor {
        id: mon
        node: root.node
        enabled: root.live
    }

    readonly property real target: {
        const p = root.live ? mon.peak : 0
        if (!(p > 0) || !(root.volume > 0)) return 0
        // volume is on the cubic (pavucontrol) scale: amplitude = volume³
        const db = 20 * Math.log10(p) + 60 * Math.log10(root.volume)
        return Math.max(0, Math.min(1, (db + 60) / 60))
    }
    // rise instantly, fall back over ~300 ms
    property real level: 0
    onTargetChanged: {
        if (target >= level) { fall.stop(); level = target }
        else { fall.to = target; fall.restart() }
    }
    NumberAnimation { id: fall; target: root; property: "level"; duration: 300; easing.type: Easing.OutQuad }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.fade(0.07)
    }
    Rectangle {
        height: parent.height
        width: parent.width * root.level
        radius: height / 2
        opacity: 0.9
        // loud (above about -6 dB) turns towards red
        color: root.level > 0.9 ? Colors.red : root.color
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
