import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.components
import qs.services

// Media player (MPRIS, like the dashboard): cover, title, artist, previous /
// play-pause / next, progress (click to seek). Follows the playing player.
RowLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 14
    readonly property var player: Media.players.find(p => p.isPlaying) ?? Media.players[0] ?? null
    readonly property bool idle: player === null
    // the frame hides the widget (not `visible`: that follows the window)
    readonly property bool hidden: idle && opts.hideIdle === true

    // MPRIS doesn't push the position: read it every second while playing
    property real position: 0
    Timer {
        running: root.active && root.player !== null && root.player.isPlaying
        interval: 1000; repeat: true; triggeredOnStart: true
        onTriggered: root.position = root.player.position
    }
    Connections { target: root.player; function onTrackTitleChanged() { root.position = root.player?.position ?? 0 } }
    readonly property real length: player && player.lengthSupported ? player.length : 0

    ClippingRectangle {
        visible: root.opts.cover !== false
        Layout.preferredWidth: 84
        Layout.preferredHeight: 84
        radius: 12
        color: Colors.fade(0.08)
        Image {
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(168, 168)
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !(root.player?.trackArtUrl)
            text: "󰎆"
            color: Colors.fade(0.4)
            font.pixelSize: 30
            font.family: Properties.fontFamily
        }
    }

    ColumnLayout {
        Layout.preferredWidth: 230
        spacing: 4
        Text {
            Layout.fillWidth: true
            text: root.idle ? "Nothing playing" : (root.player.trackTitle || "Unknown title")
            color: Colors.ink
            font.pixelSize: 15
            font.bold: true
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text: root.idle ? "Start some music" : (root.player.trackArtist || root.player.identity || "")
            color: Colors.fade(0.6)
            font.pixelSize: 12
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        // progress
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 10
            visible: root.length > 0
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4; radius: 2
                color: Colors.fade(0.15)
                Rectangle {
                    width: parent.width * Math.min(1, root.position / Math.max(1, root.length))
                    height: parent.height; radius: 2
                    color: Colors.color6
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.interactive && (root.player?.canSeek ?? false)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: m => { const p = root.length * m.x / width; root.player.position = p; root.position = p }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            IconButton {
                icon: "󰒮"; iconSize: 16
                interactive: root.interactive && (root.player?.canGoPrevious ?? false)
                onClicked: root.player.previous()
            }
            IconButton {
                implicitWidth: 40; implicitHeight: 40; iconSize: 20
                icon: root.player?.isPlaying ? "󰏤" : "󰐊"
                active: true
                interactive: root.interactive && (root.player?.canTogglePlaying ?? false)
                onClicked: root.player.togglePlaying()
            }
            IconButton {
                icon: "󰒭"; iconSize: 16
                interactive: root.interactive && (root.player?.canGoNext ?? false)
                onClicked: root.player.next()
            }
        }
    }
}
