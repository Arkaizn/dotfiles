import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// Now-playing card for the lockscreen: art, title/artist, progress and
// prev / play-pause / next. Hidden when nothing is playing.
Rectangle {
    id: root

    // the playing player, else the first one
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property real progress: player && player.lengthSupported && player.length > 0
        ? Math.min(1, player.position / player.length) : 0

    visible: player !== null
    implicitWidth: 380
    implicitHeight: 112
    radius: 20
    color: Properties.panelColor
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder

    // position only updates when asked
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && (root.player?.isPlaying ?? false)
        onTriggered: root.player.positionChanged()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // album art
        Item {
            Layout.preferredWidth: 84
            Layout.preferredHeight: 84

            Rectangle {
                id: artBg
                anchors.fill: parent
                radius: 14
                color: "#45000000"
                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "󰝚"
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 30
                    font.family: Properties.fontFamily
                }
            }
            Image {
                id: art
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                visible: art.status === Image.Ready
                source: art
                maskSource: Rectangle { width: 84; height: 84; radius: 14 }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.player?.trackTitle || "Unknown title"
                color: "white"
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.player?.trackArtist || root.player?.identity || ""
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            // progress
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 3
                radius: 2
                color: "#33ffffff"
                visible: root.player?.lengthSupported ?? false
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: 2
                    color: "#ddffffff"
                    Behavior on width { NumberAnimation { duration: 900 } }
                }
            }

            RowLayout {
                Layout.topMargin: 2
                spacing: 6
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: "󰒮"
                    interactive: root.player?.canGoPrevious ?? false
                    onClicked: root.player.previous()
                }
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: root.player?.isPlaying ? "󰏤" : "󰐊"
                    interactive: root.player?.canTogglePlaying ?? false
                    onClicked: root.player.togglePlaying()
                }
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: "󰒭"
                    interactive: root.player?.canGoNext ?? false
                    onClicked: root.player.next()
                }
            }
        }
    }
}
