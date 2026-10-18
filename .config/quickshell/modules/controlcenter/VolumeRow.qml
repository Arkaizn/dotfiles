import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.components
import qs.services

// One volume control: [mute button] [slider] [xx%]
// `node` is a Pipewire node (sink, source or app stream); it must be tracked
// by a PwObjectTracker somewhere for volume/muted to be live.
RowLayout {
    id: root

    property var node: null
    property string icon: "󰕾"
    property string mutedIcon: "󰝟"

    readonly property var audio: node?.audio ?? null
    readonly property bool muted: audio?.muted ?? false

    spacing: 8
    enabled: audio !== null

    IconButton {
        implicitWidth: 28
        implicitHeight: 28
        icon: root.muted ? root.mutedIcon : root.icon
        textColor: root.muted ? "#f38ba8" : Properties.color
        tooltip: root.muted ? "Unmute" : "Mute"
        onClicked: if (root.audio) root.audio.muted = !root.audio.muted
    }

    CCSlider {
        id: slider
        Layout.fillWidth: true
        to: Audio.maxVolume            // 1.0, or more if allowed in Settings → Audio
        scrollable: Audio.sliderScroll
        value: root.audio?.volume ?? 0
        opacity: root.muted ? 0.45 : 1
        onMoved: if (root.audio) root.audio.volume = value
    }

    Text {
        Layout.preferredWidth: 36
        horizontalAlignment: Text.AlignRight
        text: Math.round((root.audio?.volume ?? 0) * 100) + "%"
        color: Qt.rgba(1, 1, 1, root.muted ? 0.4 : 0.75)
        font.pixelSize: 11
        font.family: Properties.fontFamily
    }
}
