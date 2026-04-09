import Quickshell
import QtQuick
// import QtQuick.Shapes
// import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.services
import qs.components


Rectangle {
    implicitWidth: bar.buttonWidth + visualizer.width + albumArt.width
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[currentPlayerIndex] : null
    property bool hovered: mouseArea.containsMouse
    property int pulse: 0
    property var barHeights: [3, 3, 3]
    property int currentPlayerIndex: 0

    visible: player !== null

    gradient: ButtonGradient {
    hovered: music.hovered
    }
    Behavior on scale {
        NumberAnimation {
            duration: bar.bDuration
            easing.type: Easing.OutCubic
        } 
    }
    
    function nextPlayer() {
        if (Mpris.players.values.length > 0) {
            music.currentPlayerIndex = (music.currentPlayerIndex + 1) % Mpris.players.values.length
        }
    }

    ButtonBackground {
        id: buttonBackground
        iconText: ""
    }

    Row {
        id: layoutRow
        anchors.centerIn: parent
        spacing: 8

        Image {
            id: albumArt
            anchors.verticalCenter: parent.verticalCenter
            width: music.height * 0.75
            height: width
            source: music.player && music.player.trackArtUrl !== "" ? music.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready

            property bool rounded: true
            property bool adapt: true

            layer.enabled: rounded
            layer.effect: OpacityMask {  // for rounded corners
                maskSource: Item {
                    width: albumArt.width
                    height: albumArt.height
                    Rectangle {
                        anchors.centerIn: parent
                        width: albumArt.adapt ? albumArt.width : Math.min(albumArt.width, albumArt.height)
                        height: albumArt.adapt ? albumArt.height : width
                        radius: 8
                    }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: albumArt.status === Image.Error || albumArt.status === Image.Null
            text: "󰎇"  // nerd font music note icon
            font.pixelSize: music.height * 0.5
            color: "white"
        }

        Row {
            id: visualizer
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            height: 20

            property bool isPlaying: music.player && music.player.playbackStatus === Mpris.Playing

            Repeater {
                model: 3
                Rectangle {
                    width: 3
                    anchors.verticalCenter: parent.verticalCenter  // parent is the Row
                    height: visualizer.isPlaying ? (music.barHeights[index] ?? 3) : 3
                    radius: width / 2
                    color: "white"
                    opacity: visualizer.isPlaying ? 1.0 : 0.6

                    Behavior on height {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }
            }
        }
    }

    Process {
        id: cavaProcess
        command: ["cava", "-p", "/home/arkaizn/.config/cava/quickshell.ini"]
        running: player !== null && player.isPlaying
        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.trim().split(" ")
                if (parts.length === 3) {
                    const vals = parts.map(v => {
                        const n = parseInt(v)
                        return isNaN(n) ? 3 : Math.max(3, n)
                    })
                    music.barHeights = vals
                }
            }
        }
        onRunningChanged: {
            if (!running) music.barHeights = [3, 3, 3]
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: music.scale = bar.onEnteredButtonScale
        onPressed: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (player.isPlaying)
                music.player.pause()
                else
                music.player.play()
            } else if (mouse.button === Qt.RightButton) {
                nextPlayer()
            }
        }
        onExited: {
            music.scale = bar.onExitedButtonScale
        }
    }
}