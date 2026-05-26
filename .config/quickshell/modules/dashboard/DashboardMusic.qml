import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.services
import qs.components

Item {
    id: root
    anchors.fill: parent

    // ── Player selection ─────────────────────────────────────────────────────
    property int currentPlayerIndex: 0
    property var player: Mpris.players.values.length > 0
                         ? Mpris.players.values[currentPlayerIndex]
                         : null

    // ── Local position tracking ───────────────────────────────────────────────
    property real localPosition: 0

    // Track whether the user just seeked — suppress the next poll overwrite
    property bool seekPending: false

    function syncPosition() {
        if (root.player && root.player.lengthSupported && root.player.length > 0) {
            if (seekPending) {
                seekPending = false
                return
            }
            localPosition = root.player.position
        }
    }

    function nextPlayer() {
        if (Mpris.players.values.length > 0) {
            root.localPosition = 0
            currentPlayerIndex = (currentPlayerIndex + 1) % Mpris.players.values.length
            playerSwitchSync.restart()
        }
    }


    Timer {
        id: playerSwitchSync
        interval: 80
        repeat: false
        onTriggered: root.syncPosition()
    }

    // Reset localPosition when the track changes
    Connections {
        target: root.player
        function onTrackChanged() { root.localPosition = 0 }
    }

    // ── Blurred album art background ─────────────────────────────────────────
    Image {
        id: bgArt
        anchors.fill: parent
        source: root.player ? root.player.trackArtUrl : ""
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
        mipmap: true
        asynchronous: false
    }

    Item {
        id: blurContainer
        anchors.fill: parent
        visible: bgArt.source !== "" && bgArt.status === Image.Ready

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width:  blurContainer.width
                height: blurContainer.height
                radius: root.parent ? (root.parent.radius ?? 12) : 12
            }
        }

        FastBlur {
            anchors.fill: parent
            source: bgArt
            radius: 72
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.3)
        visible: bgArt.source === "" || bgArt.status !== Image.Ready
        radius: root.parent ? (root.parent.radius ?? 12) : 12
    }

    // ── Position polling ─────────────────────────────────────────────────────
    Timer {
        interval: 1000
        running: root.player && root.player.isPlaying
        repeat: true
        onTriggered: root.syncPosition()
    }

    // ── No player state ──────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: root.player === null
        text: "No media playing"
        color: Qt.rgba(1, 1, 1, 0.4)
        font.pixelSize: 14
    }

    // ── Main layout ──────────────────────────────────────────────────────────
    RowLayout {
        anchors {
            fill: parent
            margins: 12
        }
        spacing: 12
        visible: root.player !== null

        // Album art
        Rectangle {
            width: 130
            height: 130
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.06)
            clip: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: 130
                    height: 130
                    radius: 18
                }
            }

            Image {
                id: albumArtImage
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                asynchronous: false
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                text: "󰎇"
                font.pixelSize: 46
                color: Qt.rgba(1, 1, 1, 0.3)
                visible: !root.player || root.player.trackArtUrl === ""
                         || albumArtImage.status !== Image.Ready
            }
        }

        // Right side
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 5

            // Track title + artist
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackTitle || "Unknown title") : ""
                    color: Colors.foreground
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackArtist || "") : ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            // Source selector pill
            Rectangle {
                id: sourcePill
                Layout.alignment: Qt.AlignLeft
                height: 26
                width: pillRow.implicitWidth + 18
                radius: 8
                gradient: ButtonGradient { hovered: sourceHover.containsMouse }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                    radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                }

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 5

                    Image {
                        id: appIcon
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        sourceSize.width: 14
                        sourceSize.height: 14
                        source: {
                            if (!root.player) return ""
                            var name = (root.player.desktopEntry || root.player.identity || "").toLowerCase().trim()
                            return name !== "" ? ("https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/" + name + ".png") : ""
                        }
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    Text {
                        text: "󰝚"
                        font.pixelSize: 12
                        color: Colors.foreground
                        visible: appIcon.status !== Image.Ready
                    }

                    Text {
                        id: sourceLabel
                        text: root.player ? (root.player.identity || "Player") : "No player"
                        color: Colors.foreground
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                MouseArea {
                    id: sourceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: sourcePill.scale = 1.05
                    onExited:  sourcePill.scale = 1.0
                    onClicked: root.nextPlayer()
                }
            }

            // Controls row — shuffle / prev / play / next / repeat
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Item { Layout.fillWidth: true }

                // ── Shuffle ──────────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    gradient: ButtonGradient { hovered: shuffleHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒝"
                        font.pixelSize: 15
                        // Active = Colors.color6, inactive = dim white
                        color: root.player && root.player.shuffle
                               ? Colors.color6 : Qt.rgba(1, 1, 1, 0.35)
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: shuffleHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onClicked: {
                            if (root.player) root.player.shuffle = !root.player.shuffle
                        }
                    }
                }

                // ── Previous ─────────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    gradient: ButtonGradient { hovered: prevHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        font.pixelSize: 17
                        color: root.player && root.player.canGoPrevious
                               ? Colors.foreground : Qt.rgba(1,1,1,0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: prevHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onClicked: if (root.player && root.player.canGoPrevious) root.player.previous()
                    }
                }

                // ── Play / Pause ─────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    gradient: ButtonGradient { hovered: playHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                        font.pixelSize: 20
                        color: Colors.foreground
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: playHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onClicked: {
                            if (!root.player) return
                            if (root.player.isPlaying) root.player.pause()
                            else root.player.play()
                        }
                    }
                }

                // ── Next ─────────────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    gradient: ButtonGradient { hovered: nextHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        font.pixelSize: 17
                        color: root.player && root.player.canGoNext
                               ? Colors.foreground : Qt.rgba(1,1,1,0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: nextHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onClicked: if (root.player && root.player.canGoNext) root.player.next()
                    }
                }

                // ── Repeat ───────────────────────────────────────────────────
                // Cycles: MprisLoopState.None → All → Track → None
                Rectangle {
                    width: 34; height: 34; radius: 8
                    gradient: ButtonGradient { hovered: repeatHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        font.pixelSize: 15
                        // Icon: repeat-one for Track, repeat-all for All, repeat (dimmed) for None
                        text: {
                            if (!root.player) return "󰑖"
                            if (root.player.loopState === MprisLoopState.Track) return "󰑘"
                            return "󰑖"
                        }
                        // Color: colored for All and Track, dim for None
                        color: {
                            if (!root.player) return Qt.rgba(1, 1, 1, 0.35)
                            if (root.player.loopState === MprisLoopState.None)
                                return Qt.rgba(1, 1, 1, 0.35)
                            return Colors.color6
                        }
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.duration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: repeatHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onClicked: {
                            if (!root.player) return
                            // Cycle: None → All → Track → None
                            if (root.player.loopState === MprisLoopState.None)
                                root.player.loopState = MprisLoopState.Playlist
                            else if (root.player.loopState === MprisLoopState.Playlist)
                                root.player.loopState = MprisLoopState.Track
                            else
                                root.player.loopState = MprisLoopState.None
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Progress bar
            Item {
                Layout.fillWidth: true
                height: 5

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                Rectangle {
                    id: progressFill

                    width: {
                        if (!root.player || !root.player.lengthSupported || root.player.length <= 0)
                            return 0
                        return parent.width * Math.min(1, root.localPosition / root.player.length)
                    }
                    height: parent.height
                    radius: 3
                    color: Colors.foreground

                    Behavior on width {
                        enabled: root.player !== null && root.player.isPlaying
                        SmoothedAnimation { duration: 800; velocity: -1 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (root.player && root.player.canSeek && root.player.lengthSupported) {
                            var ratio = mouse.x / width
                            root.localPosition = ratio * root.player.length
                            root.player.position = root.localPosition
                            root.seekPending = true
                        }
                    }
                }
            }
        }
    }
}
