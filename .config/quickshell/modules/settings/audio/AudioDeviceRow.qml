import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.components
import qs.services
import "../network"
import "../../controlcenter"

// One output / input device on the audio page: default, mute, volume, test
// sound, hide from the control center, and your own name for it.
NetRow {
    id: row
    required property var node
    property bool isDefault: false
    property bool output: true
    signal makeDefault()

    property bool renaming: false
    readonly property var audio: node?.audio ?? null

    wide: true
    label: Audio.label(node) + (isDefault ? "  ·  default" : "")
    desc: (Audio.names[node.name] ? node.description + "  ·  " : "") + node.name + (Audio.isHidden(node) ? "  ·  hidden in the control center" : "")

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        IconButton {
            icon: row.isDefault ? "󰄬" : "󰄱"
            tooltip: row.isDefault ? "Default device" : "Make default"
            active: row.isDefault
            onClicked: row.makeDefault()
        }
        IconButton {
            icon: row.audio?.muted ? (row.output ? "󰝟" : "󰍭") : (row.output ? "󰕾" : "󰍬")
            textColor: row.audio?.muted ? "#f38ba8" : Properties.color
            tooltip: row.audio?.muted ? "Unmute" : "Mute"
            onClicked: if (row.audio) row.audio.muted = !row.audio.muted
        }
        CCSlider {
            Layout.fillWidth: true
            visible: !row.renaming
            to: Audio.maxVolume
            scrollable: Audio.sliderScroll
            value: row.audio?.volume ?? 0
            opacity: row.audio?.muted ? 0.45 : 1
            onMoved: if (row.audio) row.audio.volume = value
        }
        Text {
            visible: !row.renaming
            Layout.preferredWidth: 42
            text: Math.round((row.audio?.volume ?? 0) * 100) + "%"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 12
            font.family: Properties.fontFamily
            horizontalAlignment: Text.AlignRight
        }
        SearchField {
            id: nameField
            Layout.fillWidth: true
            visible: row.renaming
            icon: ""
            placeholderText: row.node.description
            onAccepted: { Audio.rename(row.node, text); row.renaming = false }
        }
        IconButton {
            icon: row.renaming ? "󰄬" : "󰏫"
            tooltip: row.renaming ? "Save the name (empty = original)" : "Rename"
            onClicked: {
                if (row.renaming) { Audio.rename(row.node, nameField.text); row.renaming = false }
                else { nameField.text = Audio.names[row.node.name] ?? ""; row.renaming = true; nameField.forceActiveFocus() }
            }
        }
        IconButton {
            visible: row.output
            icon: "󰓃"
            tooltip: "Play a test sound on it"
            onClicked: Audio.testSound(row.node)
        }
        IconButton {
            icon: Audio.isHidden(row.node) ? "󰈉" : "󰈈"
            tooltip: Audio.isHidden(row.node) ? "Show in the control center" : "Hide in the control center"
            onClicked: Audio.setHidden(row.node, !Audio.isHidden(row.node))
        }
    }
}
