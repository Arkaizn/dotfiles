import Quickshell
import QtQuick
// import QtQuick.Shapes
// import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.services
import qs.components


Rectangle {
    implicitWidth: albumArt.width + buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: bar.spacing
    anchors.right: clock.left  // stuck to the left of clock

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property bool hovered: mouseArea.containsMouse

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
        hovered: music.hovered
        iconText: player
        iconSize: bar.iconSize
    }

    Image {
        id: albumArt
        anchors.centerIn: parent
        width: parent.height * 0.75
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