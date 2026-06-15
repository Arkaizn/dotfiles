import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Pipewire

Rectangle {
    id: root
    signal cycleOutputRequested(int delta)

    implicitHeight: outputInner.implicitHeight + 24
    radius: 10
    color: "#27000000"

    // Reactive list of real output devices
    property var outputSinks: {
        const list = Pipewire.nodes.values.filter(node => {
            return node.audio &&
                   node.isSink &&
                   !node.isStream &&
                   !node.name.includes("monitor") &&
                   !node.name.includes("virtual") &&
                   node.properties &&
                   (node.properties["media.class"] === "Audio/Sink" ||
                    node.properties["node.name"]?.includes("alsa_output"));
        }).sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""));

        console.log("OutputCard sinks updated:", list.map(s => s.description || s.name));
        return list;
    }

    ColumnLayout {
        id: outputInner
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 10

        // ── Device row (◀ name ▶) ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "◀"
                color: "#88ffffff"
                font.pixelSize: 16
                opacity: outputSinks.length > 1 ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: outputSinks.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (outputSinks.length > 1) root.cycleOutputRequested(-1)
                    hoverEnabled: outputSinks.length > 1
                }
            }

            Text {
                text: {
                    const s = Pipewire.defaultAudioSink
                    return s?.description ?? s?.name ?? "No output device"
                }
                color: "#cdffffff"
                font.pixelSize: 13
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                text: "▶"
                color: "#88ffffff"
                font.pixelSize: 16
                opacity: outputSinks.length > 1 ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: outputSinks.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (outputSinks.length > 1) root.cycleOutputRequested(1)
                    hoverEnabled: outputSinks.length > 1
                }
            }
        }

        Slider {
            id: outputVolumeSlider
            Layout.fillWidth: true
            from: 0.0
            to: 1.0
            value: Pipewire.defaultAudioSink?.audio?.volume ?? 0

            onValueChanged: {
                if (pressed && Pipewire.defaultAudioSink?.audio) {
                    Pipewire.defaultAudioSink.audio.volume = value
                }
            }

            Connections {
                target: Pipewire
                function onDefaultAudioSinkChanged() {
                    outputVolumeSlider.value = Pipewire.defaultAudioSink?.audio?.volume ?? 0
                }
            }

            Connections {
                target: Pipewire.defaultAudioSink?.audio ?? null
                function onVolumeChanged() {
                    if (!outputVolumeSlider.pressed)
                        outputVolumeSlider.value = Pipewire.defaultAudioSink.audio.volume
                }
            }

            background: Rectangle {
                implicitHeight: 4
                width: parent.width
                y: (parent.height - height) / 2
                radius: 2
                color: "#33ffffff"
                Rectangle {
                    width: outputVolumeSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: "#ddffffff"
                }
            }

            handle: Rectangle {
                implicitWidth: 18
                implicitHeight: 18
                x: outputVolumeSlider.leftPadding + outputVolumeSlider.visualPosition * (outputVolumeSlider.availableWidth - width)
                y: (outputVolumeSlider.height - height) / 2
                radius: 9
                color: outputVolumeSlider.pressed ? "#ffffff" : "#eeffffff"
                border.color: "#55ffffff"
                border.width: 1
            }
        }
    }
}