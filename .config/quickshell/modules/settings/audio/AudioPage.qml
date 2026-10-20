import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.components
import qs.services
import ".."
import "../network"
import "../../controlcenter"

// Audio page (services/Audio.qml): every output / input with volume, default,
// mute, name and visibility; apps playing right now; card profiles; scroll
// step and max volume. Every slider has a live level meter (LevelMeter).
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: Audio.loadCards()

    // apps playing audio right now (not the recording mix, not speech-dispatcher)
    readonly property var streams: Pipewire.nodes.values
        .filter(n => n.type === PwNodeType.AudioOutStream && !n.name.startsWith("speech-dispatcher") && !Audio.isInternal(n))

    // volume / mute only update for tracked nodes
    PwObjectTracker { objects: Audio.sinks.concat(Audio.sources).concat(page.streams) }

    NativeAppCard {
        app: "pavucontrol"
        label: "PipeWire volume control"
        desc: "Every device, stream and port in detail"
    }

    NetCard {
        Layout.fillWidth: true
        title: "Volume"
        NetRow {
            first: true
            label: "Scroll step"
            desc: "% per wheel notch on the bar's volume button"
            NumberControl { from: 1; to: 20; value: Math.round(Audio.step * 100); onEdited: v => Settings.set("audio", "step", Math.round(v)) }
        }
        NetRow {
            label: "Maximum volume"
            desc: Audio.maxVolume > 1 ? "above 100% can distort" : "sliders and scrolling stop at 100%"
            NumberControl { from: 100; to: 150; step: 5; value: Math.round(Audio.maxVolume * 100); onEdited: v => Settings.set("audio", "maxVolume", Math.round(v / 5) * 5) }
        }
        NetRow {
            label: "Scroll on volume sliders"
            desc: Audio.sliderScroll ? "the mouse wheel over a slider changes the volume (here and in the control center)"
                                     : "off: the mouse wheel scrolls the page; drag the sliders to change the volume"
            ToggleSwitch { checked: Audio.sliderScroll; onToggled: v => Settings.set("audio", "sliderScroll", v) }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Output devices"
        icon: "󰓃"
        NetRow { first: true; visible: Audio.sinks.length === 0; label: "No output devices"; desc: "is PipeWire running?" }
        Repeater {
            model: Audio.sinks
            AudioDeviceRow {
                required property var modelData
                required property int index
                node: modelData
                first: index === 0
                output: true
                isDefault: modelData === Pipewire.defaultAudioSink
                onMakeDefault: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Input devices"
        icon: "󰍬"
        NetRow { first: true; visible: Audio.sources.length === 0; label: "No input devices" }
        Repeater {
            model: Audio.sources
            AudioDeviceRow {
                required property var modelData
                required property int index
                node: modelData
                first: index === 0
                output: false
                isDefault: modelData === Pipewire.defaultAudioSource
                onMakeDefault: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Apps"
        icon: "󰎆"
        NetRow { first: true; visible: page.streams.length === 0; label: "Nothing is playing"; desc: "apps show up here while they play sound" }
        Repeater {
            model: page.streams
            NetRow {
                required property var modelData
                required property int index
                readonly property var props: modelData.properties ?? {}
                first: index === 0
                wide: true
                label: props["application.name"] || props["application.process.binary"] || modelData.description || modelData.name
                desc: props["media.name"] ?? ""
                VolumeRow { Layout.fillWidth: true; node: modelData }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Sound cards"
        header: ActionButton { icon: "󰑓"; text: "Reload"; onClicked: Audio.loadCards() }
        NetRow { first: true; visible: Audio.cardError !== ""; label: "Can't read the cards"; desc: Audio.cardError }
        Repeater {
            model: Audio.cards
            NetRow {
                required property var modelData
                required property int index
                first: index === 0 && Audio.cardError === ""
                label: modelData.description
                desc: "profile: what the card offers (outputs, inputs, channels); Off frees it"
                DropdownControl {
                    options: modelData.profiles.filter(p => p.available || p.name === modelData.active)
                                               .map(p => ({ label: p.description, value: p.name }))
                    value: modelData.active
                    onEdited: v => Audio.setProfile(modelData.name, v)
                }
            }
        }
    }
}
