import Quickshell
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.services
import qs.components


Rectangle {
    // implicitWidth: bar.buttonWidth + visualizer.width + albumArt.width
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius

    implicitWidth: expanded ? bar.buttonWidth + visualizer.width + albumArt.width + controlsRow.width + 10
                            : bar.buttonWidth + visualizer.width + albumArt.width 

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[currentPlayerIndex] : null
    property bool hovered: hoverHandler.hovered   // back to real hover for gradient
    property bool expanded: false
    property int pulse: 0
    property var barHeights: [3, 3, 3]
    property int currentPlayerIndex: 0

    visible: player !== null

    // animation for hover effect
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

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

    Item {
        anchors.fill: parent
        anchors.verticalCenter: parent.verticalCenter

        Image {
            id: albumArt
            anchors.left: parent.left
            anchors.leftMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: music.height * 0.75
            height: width
            source: music.player && music.player.trackArtUrl !== "" ? music.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready

            property bool rounded: true
            property bool adapt: true

            layer.enabled: rounded
            layer.effect: OpacityMask {
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
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: albumArt.status === Image.Error || albumArt.status === Image.Null
            text: "󰎇"  // nerd font music note icon
            font.pixelSize: music.height * 0.5
            color: "white"
        }

        Row {
            id: visualizer
            anchors.right: parent.right
            anchors.rightMargin: 10
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
    

        // Media controls — fade + slide in on hover
        Row {
            id: controlsRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            anchors.centerIn: parent
            opacity: music.expanded ? 1.0 : 0.0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 0; easing.type: Easing.OutCubic }
            }

            // Previous
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒮"   // nerd font: skip-previous
                font.pixelSize: bar.pixelSize +7 //music.height * 0.38
                color: "white"
                opacity: prevHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: music.player.previous()
                }
            }

            // Play / Pause
            Text {
                anchors.verticalCenter: parent.verticalCenter
                property bool isPlaying: music.player && music.player.playbackStatus === Mpris.Playing
                text: player ? player.isPlaying : false ? "" : ""  // pause : play
                font.pixelSize: bar.pixelSize + 3
                color: "white"
                opacity: playHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: playHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            if (player ? player.isPlaying : false)
                            music.player.pause()
                            else
                            music.player.play()
                        }
                    }

                }
            }

            // Next
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒭"   // nerd font: skip-next
                font.pixelSize: bar.pixelSize +7
                color: "white"
                opacity: nextHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: music.player && music.player.next()
                }
            }
        }
    }
    
    Process {
        id: cavaProcess
        command: ["cava", "-p", "/home/arkaizn/.config/cava/quickshell.ini"]
        running: player !== null && player ? player.isPlaying : false
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

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: music.scale = hovered ? bar.onEnteredButtonScale : bar.onExitedButtonScale
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.RightButton)
                nextPlayer()
            else if (button === Qt.LeftButton)
                music.expanded = !music.expanded
        }
    }
}