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
    Behavior on opacity { NumberAnimation { duration: Anim.normal } }

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
    // rise instantly, fall back over ~300 ms. Stepped 30 times a second, not
    // animated per display frame: the meter moves all the time while a
    // microphone is open, and per frame that made the whole control center redraw
    // 360 times a second on a fast monitor (about 30 % of a core while it was open).
    property real level: 0
    Timer {
        interval: 33
        repeat: true
        running: root.live || root.level > 0
        onTriggered: {
            const t = root.target
            let next = t >= root.level ? t : root.level - Math.max(0.012, (root.level - t) * 0.24)
            if (next - t < 0.004) next = t
            // (less than a pixel of the bar isn't worth a redraw)
            if (Math.abs(next - root.level) * root.width >= 0.5 || next === 0 || next === t) root.level = next
        }
    }

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
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }
}
