import Quickshell
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
import qs.components

// Media player on the bar: album art + a 3-bar visualizer (Media's shared
// cava). Left click: show the controls · right click: next player.
// Sources: Media.sources (local players, and remote sessions through the
// mediasync bridge; then the selection is the bridge's, shared with the dashboard).
// Own button behaviour (not BarButton): its controls take clicks.
Item {
    id: music
    // implicitWidth: Properties.buttonWidth + visualizer.width + albumArt.width
    implicitHeight: Properties.buttonHeight

    implicitWidth: expanded ? Properties.buttonWidth + visualizer.width + albumArt.width + controlsRow.width + 10
                            : Properties.buttonWidth + visualizer.width + albumArt.width 

    readonly property var players: Media.sources
    readonly property var player: Media.bridgeActive ? Media.selected
                                : players.length > 0 ? players[Math.min(currentPlayerIndex, players.length - 1)] : null
    property bool hovered: hoverHandler.hovered   // back to real hover for gradient
    property bool expanded: false
    property int currentPlayerIndex: 0
    readonly property bool isPlaying: player?.isPlaying ?? false
    // cava hears this computer only: real levels while it hears something,
    // else (remote session, muted player) the bars play their own animation
    readonly property bool hearsIt: isPlaying && !(player?.remote ?? false) && Media.visualizerLive

    Component.onCompleted: Media.acquireVisualizer()
    Component.onDestruction: Media.releaseVisualizer()

    visible: player !== null

    // animation for hover effect
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    // needs to be here because of the albim image that cannot be passed to the buttonBackground
    Behavior on scale {
        NumberAnimation {
            duration: Properties.bDuration
            easing.type: Easing.OutCubic
        }
    }

    function nextPlayer() {
        if (music.players.length === 0) return
        if (Media.bridgeActive) Media.selectNext()
        else music.currentPlayerIndex = (music.currentPlayerIndex + 1) % music.players.length
    }

    ButtonBackground {
        id: buttonBackground
        iconText: ""
        hovered: music.hovered
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
            text: Icons.get("music")
            font.pixelSize: music.height * 0.5
            color: Properties.color
        }

        // remote session (e.g. the phone): a small marker on the cover
        Rectangle {
            visible: music.player?.remote ?? false
            x: albumArt.x + albumArt.width - width + 3
            y: albumArt.y + albumArt.height - height + 3
            width: 13; height: 13; radius: 7
            color: Colors.color6
            Text {
                anchors.centerIn: parent
                text: Icons.get("mediaRemote")
                font.pixelSize: 9
                color: Colors.background
            }
        }

        Row {
            id: visualizer
            anchors.right: parent.right
            anchors.rightMargin: 10
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            height: 20

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 3
                    anchors.verticalCenter: parent.verticalCenter  // parent is the Row
                    height: music.hearsIt ? (Media.visualizer[index] ?? 3) : music.isPlaying ? bounce : 3
                    radius: width / 2
                    color: Properties.color
                    opacity: music.isPlaying ? 1.0 : 0.6

                    // the "playing" animation: each bar its own speed and height
                    property real bounce: 4
                    SequentialAnimation on bounce {
                        id: bounceAnim
                        running: music.visible && music.isPlaying && !music.hearsIt
                        loops: Animation.Infinite
                        NumberAnimation { to: [13, 17, 11][index]; duration: [540, 430, 650][index]; easing.type: Easing.InOutSine }
                        NumberAnimation { to: [5, 7, 4][index]; duration: [480, 580, 450][index]; easing.type: Easing.InOutSine }
                        NumberAnimation { to: [9, 12, 15][index]; duration: [420, 500, 560][index]; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4; duration: [510, 390, 480][index]; easing.type: Easing.InOutSine }
                    }

                    Behavior on height {
                        enabled: !bounceAnim.running      // the bounce is smooth already
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
                text: Icons.get("previous")
                font.pixelSize: Properties.pixelSize +7 //music.height * 0.38
                color: Properties.color
                opacity: !(music.player?.canGoPrevious ?? false) ? 0.25 : prevHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (music.player?.canGoPrevious) music.player.previous()
                }
            }

            // Play / Pause
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: music.isPlaying ? Icons.get("pause") : Icons.get("play")
                font.pixelSize: Properties.pixelSize + 3
                color: Properties.color
                opacity: music.player?.remote && !music.player.canTogglePlaying ? 0.25 : playHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: playHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // on click, like the other controls
                    onClicked: {
                        if (music.isPlaying) music.player?.pause()
                        else music.player?.play()
                    }
                }
            }

            // Next
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.get("next")
                font.pixelSize: Properties.pixelSize +7
                color: Properties.color
                opacity: !(music.player?.canGoNext ?? false) ? 0.25 : nextHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (music.player?.canGoNext) music.player.next()
                }
            }
        }
    }
    
    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    scale: tapHandler.pressed ? Properties.onPressedButtonScale
         : hoverHandler.hovered ? Properties.onEnteredButtonScale
         : Properties.onExitedButtonScale

    TapHandler {
        id: tapHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.RightButton)
                nextPlayer()
            else if (button === Qt.LeftButton)
                music.expanded = !music.expanded
        }
    }
}