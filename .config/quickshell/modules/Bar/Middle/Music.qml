import Quickshell
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
import qs.components

// Media player on the bar: album art + a 3-bar visualizer (Media's shared
// cava). Left click: show the controls · right click: next player.
// Own button behaviour (not BarButton): its controls take clicks.
Item {
    id: music
    // implicitWidth: Properties.buttonWidth + visualizer.width + albumArt.width
    implicitHeight: Properties.buttonHeight

    implicitWidth: expanded ? Properties.buttonWidth + visualizer.width + albumArt.width + controlsRow.width + 10
                            : Properties.buttonWidth + visualizer.width + albumArt.width 

    readonly property var players: Media.players
    property var player: players.length > 0 ? players[Math.min(currentPlayerIndex, players.length - 1)] : null
    property bool hovered: hoverHandler.hovered   // back to real hover for gradient
    property bool expanded: false
    property int currentPlayerIndex: 0
    readonly property bool isPlaying: player?.isPlaying ?? false

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
        if (music.players.length > 0) {
            music.currentPlayerIndex = (music.currentPlayerIndex + 1) % music.players.length
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
            text: Icons.get("music")
            font.pixelSize: music.height * 0.5
            color: Colors.ink
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
                    width: 3
                    anchors.verticalCenter: parent.verticalCenter  // parent is the Row
                    height: music.isPlaying ? (Media.visualizer[index] ?? 3) : 3
                    radius: width / 2
                    color: Colors.ink
                    opacity: music.isPlaying ? 1.0 : 0.6

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
                text: Icons.get("previous")
                font.pixelSize: Properties.pixelSize +7 //music.height * 0.38
                color: Colors.ink
                opacity: prevHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: music.player?.previous()
                }
            }

            // Play / Pause
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: music.isPlaying ? Icons.get("pause") : Icons.get("play")
                font.pixelSize: Properties.pixelSize + 3
                color: Colors.ink
                opacity: playHover.containsMouse ? 1.0 : 0.65

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
                color: Colors.ink
                opacity: nextHover.containsMouse ? 1.0 : 0.65

                Behavior on opacity { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: music.player?.next()
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