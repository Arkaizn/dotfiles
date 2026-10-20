import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// Now-playing card for the lockscreen: art, title/artist, seekable progress,
// shuffle / prev / play-pause / next / repeat and a player switcher (same
// features as DashboardMusic). Hidden when nothing is playing.
Rectangle {
    id: root

    // the player shown: the one that last started playing or was picked with
    // the switch button. Sticks when paused/stopped so it doesn't jump to
    // another player; only changes when a player starts playing or it closes.
    readonly property var players: Media.players
    property bool controls: true        // false: only what's playing (Settings → Lockscreen)
    property var selectedPlayer: null
    readonly property var player: (selectedPlayer && root.players.includes(selectedPlayer) ? selectedPlayer : null)
        ?? root.players.find(p => p.isPlaying) ?? root.players[0] ?? null
    // remember whatever is shown, so pausing it doesn't fall back to another player
    // (later: not inside the binding's own update; a member function, so it
    // doesn't run against a destroyed card after unlocking)
    onPlayerChanged: Qt.callLater(root.rememberPlayer)
    function rememberPlayer() { if (root.player && root.selectedPlayer !== root.player) root.selectedPlayer = root.player }

    // switch to a player when it starts playing
    Instantiator {
        model: Media.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { if (modelData.isPlaying) root.selectedPlayer = modelData }
        }
    }
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

    function nextPlayer() {
        const players = root.players
        if (players.length < 2) return
        root.selectedPlayer = players[(players.indexOf(root.player) + 1) % players.length]
    }

    function cycleLoop() {
        if (root.player.loopState === MprisLoopState.None)
            root.player.loopState = MprisLoopState.Playlist
        else if (root.player.loopState === MprisLoopState.Playlist)
            root.player.loopState = MprisLoopState.Track
        else
            root.player.loopState = MprisLoopState.None
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

                // click to seek; taller than the bar so it's easy to hit
                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -6
                    anchors.bottomMargin: -6
                    enabled: root.controls && (root.player?.canSeek ?? false)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        const ratio = Math.max(0, Math.min(1, mouse.x / width))
                        root.player.position = ratio * root.player.length
                        root.player.positionChanged()
                    }
                }
            }

            RowLayout {
                visible: root.controls
                Layout.topMargin: 2
                spacing: 6
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: "󰒝"
                    tooltip: "Shuffle"
                    textColor: root.player?.shuffle ? Colors.color6 : Properties.color
                    interactive: (root.player?.canControl ?? false) && (root.player?.shuffleSupported ?? false)
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
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
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: root.player?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                    tooltip: "Repeat"
                    textColor: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                        ? Colors.color6 : Properties.color
                    interactive: (root.player?.canControl ?? false) && (root.player?.loopSupported ?? false)
                    onClicked: root.cycleLoop()
                }
                // only shown when there's more than one player to switch between
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    visible: root.players.length > 1
                    icon: "󰓃"
                    tooltip: root.player?.identity ?? "Switch player"
                    onClicked: root.nextPlayer()
                }
            }
        }
    }
}
