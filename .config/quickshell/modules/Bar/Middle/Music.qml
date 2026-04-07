import Quickshell
import QtQuick
// import QtQuick.Shapes
// import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.services
import qs.components


Rectangle {
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth + visualizer.width + albumArt.width
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: bar.spacing
    anchors.right: clock.left  // stuck to the left of clock

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property bool hovered: mouseArea.containsMouse
    property int pulse: 0
    property var barHeights: [3, 3, 3]

    visible: music.player !== null && music.player.trackArtUrl !== ""

    gradient: ButtonGradient {
    hovered: music.hovered
    }
    Behavior on scale {
        NumberAnimation {
            duration: bar.bDuration
            easing.type: Easing.OutCubic
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
            anchors.centerIn: music
            width: music.height * 0.75
            height: width
            source: music.player ? music.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop

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
                    opacity: player.isPlaying ? 1.0 : 0.6

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

    Timer {
    interval: 120
    running: player.isPlaying === true
    repeat: true
    onTriggered: {
        music.barHeights = [
            Math.random() * 13 + 4,
            Math.random() * 13 + 4,
            Math.random() * 13 + 4
        ]
    }
    
        onRunningChanged: {
            if (!running) {
                music.barHeights = [3, 3, 3]  // reset to dots when stopped
            }
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: music.scale = bar.onEnteredButtonScale
        onClicked: {

        }
        onExited: {
            music.scale = bar.onExitedButtonScale
        }
    }
}