import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.services
import qs.components

Item {
    id: root
    anchors.fill: parent

    // set by the dashboard: true while it's open (position polling only then)
    property bool active: false

    // ── Player selection ─────────────────────────────────────────────────────
    // Media.sources: local players, plus remote sessions through the mediasync
    // bridge (services/MediaSource.qml). With the bridge, the source is the
    // bridge's selection (shared with the bar); without it, this card's own pick.
    property int currentPlayerIndex: 0
    readonly property var players: Media.sources
    readonly property var player: Media.bridgeActive ? Media.selected
                                : players.length > 0 ? players[Math.min(currentPlayerIndex, players.length - 1)] : null
    // the bridge is on in settings but not reachable: local players only (MEDIASYNC.md)
    readonly property bool bridgeOffline: MediaSync.state === "unavailable"

    // ── Local position tracking ───────────────────────────────────────────────
    property real localPosition: 0
    property bool positionKnown: true       // false: a remote session that stopped reporting

    // Track whether the user just seeked — suppress the next poll overwrite
    property bool seekPending: false

    function syncPosition() {
        if (root.player && root.player.lengthSupported && root.player.length > 0) {
            if (seekPending) {
                seekPending = false
                return
            }
            const p = root.player.positionNow()
            root.positionKnown = p >= 0
            localPosition = Math.max(0, p)
        }
    }

    // a failed command of the shown session, for a few seconds instead of the artist
    property string errorText: ""
    Connections {
        target: MediaSync
        function onLastErrorChanged() {
            if (MediaSync.lastError && root.player && MediaSync.lastError.sessionId === root.player.sessionId) {
                root.errorText = MediaSync.lastError.text
                errorClear.restart()
            }
        }
    }
    Timer { id: errorClear; interval: 4000; onTriggered: root.errorText = "" }

    // Bring the player to the front: MPRIS Raise first (Firefox / Zen switch to
    // the playing tab), then focus its window through the compositor — on Wayland an app
    // usually can't put itself in front. The window is found by app id
    // (desktop entry or player name); with several windows (browser), the one
    // whose title has the track in it wins (= the playing tab).
    function jumpToPlayer() {
        const p = root.player
        if (!p || p.remote) return
        if (p.canRaise) p.raise()
        const key = (p.desktopEntry || p.identity || "").toLowerCase().replace(/^mozilla\s+/, "")
        // waits a moment first: the browser switches tab (its title changes)
        Compositor.focusAppWindow(key, p.trackTitle || "", () => Panels.close("dashboard"))
    }

    function nextPlayer() {
        if (root.players.length > 0) {
            root.localPosition = 0
            root.errorText = ""
            if (Media.bridgeActive) Media.selectNext()
            else currentPlayerIndex = (currentPlayerIndex + 1) % root.players.length
            playerSwitchSync.restart()
        }
    }
    onPlayerChanged: { root.errorText = ""; playerSwitchSync.restart() }


    Timer {
        id: playerSwitchSync
        interval: 80
        repeat: false
        onTriggered: root.syncPosition()
    }

    // Reset localPosition when the track changes
    Connections {
        target: root.player
        function onTrackKeyChanged() { root.localPosition = 0; playerSwitchSync.restart() }
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
        running: root.active && root.player !== null && root.player.isPlaying
        repeat: true
        triggeredOnStart: true      // up to date as soon as the dashboard opens
        onTriggered: root.syncPosition()
    }

    // ── No player state ──────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: root.player === null
        text: "No media playing"
        color: Colors.fade(0.4)
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
            id: artBox
            width: 130
            height: 130
            radius: 18
            color: Colors.fade(0.06)
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
                color: Colors.fade(0.3)
                visible: !root.player || root.player.trackArtUrl === ""
                         || albumArtImage.status !== Image.Ready
            }

            // volume: scroll on the cover (only players that support it); the
            // value shows for a moment. Remote volume is sent once scrolling pauses.
            property real pendingVolume: -1
            readonly property real shownVolume: pendingVolume >= 0 ? pendingVolume : (root.player?.volume ?? 0)
            WheelHandler {
                enabled: root.player !== null && root.player.canSetVolume
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const art = artBox
                    const step = (event.angleDelta.y > 0 ? 1 : -1) * 0.05
                    art.pendingVolume = Math.max(0, Math.min(1, Math.round((art.shownVolume + step) * 20) / 20))
                    volumeSend.restart()
                    volumeShow.restart()
                }
            }
            Timer {
                id: volumeSend
                interval: 250
                onTriggered: {
                    const art = artBox
                    if (root.player && art.pendingVolume >= 0) root.player.setVolume(art.pendingVolume)
                }
            }
            Timer { id: volumeShow; interval: 1200; onTriggered: artBox.pendingVolume = -1 }
            Rectangle {
                anchors.centerIn: parent
                width: volLabel.implicitWidth + 18; height: 26; radius: 8
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: volumeShow.running ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Text {
                    id: volLabel
                    anchors.centerIn: parent
                    text: "󰕾  " + Math.round(artBox.shownVolume * 100) + "%"
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }
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
                    color: Properties.color
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                // always takes its line (even without an artist), so the
                // buttons below don't move between tracks / players
                Text {
                    Layout.fillWidth: true
                    text: root.errorText !== "" ? root.errorText : root.player ? (root.player.trackArtist || " ") : " "
                    color: root.errorText !== "" ? Colors.red : Colors.fade(0.55)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            // source pill (switches player) + jump to the player
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: 6

            Rectangle {
                id: sourcePill
                Layout.alignment: Qt.AlignLeft
                // implicit size: the row lays it out to fit the icon + player name
                implicitHeight: 26
                implicitWidth: pillRow.implicitWidth + 18
                radius: 8
                border.color: Colors.fade(sourceHover.containsMouse ? 0.28 : 0.18)
                border.width: 0.5
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
                        // Local icon theme lookup via the player's .desktop entry. (Was a CDN
                        // URL: a network fetch on every reload that 404'd for some players,
                        // and the only async image load in the config — a suspect for the
                        // reload crash in QQuickPixmap::connectFinished.)
                        source: {
                            if (!root.player || root.player.remote) return ""
                            var id = (root.player.desktopEntry || root.player.identity || "").trim()
                            if (id === "") return ""
                            var icon = DesktopEntries.byId(id)?.icon ?? id.toLowerCase()
                            return Quickshell.iconPath(icon, true)
                        }
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    Text {
                        text: root.player?.remote ? Icons.get("mediaRemote") : "󰝚"
                        font.pixelSize: 12
                        color: root.player?.remote ? Colors.color6 : Properties.color
                        visible: appIcon.status !== Image.Ready
                    }

                    Text {
                        id: sourceLabel
                        // remote: "Finamp · Pixel 7" — where it plays matters more than the app
                        text: !root.player ? "No player"
                            : root.player.remote ? root.player.identity + (root.player.session?.player?.device ? " · " + root.player.session.player.device : "")
                            : (root.player.identity || "Player")
                        color: Properties.color
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                MouseArea {
                    id: sourceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: sourcePill.scale = 1.05
                    onExited:  sourcePill.scale = 1.0
                    onPressed: sourcePill.scale = Properties.onPressedButtonScale
                    onReleased: sourcePill.scale = containsMouse ? 1.05 : 1.0
                    onCanceled: sourcePill.scale = 1.0
                    onClicked: root.nextPlayer()
                }
            }

            // jump to the player: its window (and in a browser the playing tab)
            Rectangle {
                id: jumpBtn
                visible: root.player !== null && !root.player.remote
                implicitWidth: 26; implicitHeight: 26
                radius: 8
                border.color: Colors.fade(jumpHover.containsMouse ? 0.28 : 0.18)
                border.width: 0.5
                gradient: ButtonGradient { hovered: jumpHover.containsMouse }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                    radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                }
                Text {
                    anchors.centerIn: parent
                    text: "󰏌"
                    font.pixelSize: 13
                    color: Properties.color
                }
                Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                MouseArea {
                    id: jumpHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: jumpBtn.scale = 1.1
                    onExited:  jumpBtn.scale = 1.0
                    onPressed: jumpBtn.scale = Properties.onPressedButtonScale
                    onReleased: jumpBtn.scale = containsMouse ? 1.1 : 1.0
                    onCanceled: jumpBtn.scale = 1.0
                    onClicked: root.jumpToPlayer()
                }
            }

            // view only / not reporting / bridge offline: says why the controls are off
            Text {
                readonly property string note: root.player?.viewOnly ? (root.player.stale ? "not reporting" : "view only")
                                             : root.bridgeOffline ? "mediasync offline" : ""
                visible: note !== ""
                text: note
                color: Colors.fade(0.45)
                font.pixelSize: 10
                font.italic: true
            }
            }

            // fixed gap: the controls sit at the same place whatever is shown above
            Item { Layout.preferredHeight: 6 }

            // Controls row — shuffle / prev / play / next / repeat
            RowLayout {
                Layout.fillWidth: true
                transform: Translate { y: -4 }      // a touch higher, with the bar below
                spacing: 4

                Item { Layout.fillWidth: true }

                // ── Shuffle ──────────────────────────────────────────────────
                Rectangle {
                    width: 34
                    height: 34
                    radius: 8
                    border.color: Colors.fade(shuffleHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
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
                               ? Colors.color6 : Colors.fade(0.35)
                        // remote sessions show their shuffle state but can't change it (no bridge command)
                        opacity: root.player && root.player.remote ? 0.4 : 1
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: shuffleHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onPressed: parent.scale = Properties.onPressedButtonScale
                        onReleased: parent.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: parent.scale = 1.0
                        onClicked: {
                            if (root.player) root.player.setShuffle(!root.player.shuffle)
                        }
                    }
                }

                // ── Previous ─────────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    border.color: Colors.fade(prevHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
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
                               ? Properties.color : Colors.fade(0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: prevHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onPressed: parent.scale = Properties.onPressedButtonScale
                        onReleased: parent.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: parent.scale = 1.0
                        onClicked: if (root.player && root.player.canGoPrevious) root.player.previous()
                    }
                }

                // ── Play / Pause ─────────────────────────────────────────────
                Rectangle {
                    width: 34; height: 34; radius: 8
                    border.color: Colors.fade(playHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: playHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: 8; color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                        font.pixelSize: 20
                        color: !root.player || root.player.mpris || root.player.canTogglePlaying
                               ? Properties.color : Colors.fade(0.25)
                        // a remote command waits for the phone to confirm (up to a few seconds)
                        opacity: root.player?.busy ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: playHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onPressed: parent.scale = Properties.onPressedButtonScale
                        onReleased: parent.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: parent.scale = 1.0
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
                    border.color: Colors.fade(nextHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
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
                               ? Properties.color : Colors.fade(0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: nextHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onPressed: parent.scale = Properties.onPressedButtonScale
                        onReleased: parent.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: parent.scale = 1.0
                        onClicked: if (root.player && root.player.canGoNext) root.player.next()
                    }
                }

                // ── Repeat ───────────────────────────────────────────────────
                // Cycles: MprisLoopState.None → All → Track → None
                Rectangle {
                    width: 34; height: 34; radius: 8
                    border.color: Colors.fade(repeatHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
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
                            if (!root.player) return Colors.fade(0.35)
                            if (root.player.loopState === MprisLoopState.None)
                                return Colors.fade(0.35)
                            return Colors.color6
                        }
                        opacity: root.player && root.player.remote ? 0.4 : 1
                    }
                    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        id: repeatHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.scale = 1.1
                        onExited:  parent.scale = 1.0
                        onPressed: parent.scale = Properties.onPressedButtonScale
                        onReleased: parent.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: parent.scale = 1.0
                        onClicked: {
                            if (!root.player) return
                            // Cycle: None → All → Track → None
                            if (root.player.loopState === MprisLoopState.None)
                                root.player.setLoop(MprisLoopState.Playlist)
                            else if (root.player.loopState === MprisLoopState.Playlist)
                                root.player.setLoop(MprisLoopState.Track)
                            else
                                root.player.setLoop(MprisLoopState.None)
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
                    color: Colors.fade(0.12)
                }

                Rectangle {
                    id: progressFill

                    width: {
                        if (!root.player || !root.player.lengthSupported || root.player.length <= 0 || !root.positionKnown)
                            return 0
                        return parent.width * Math.min(1, root.localPosition / root.player.length)
                    }
                    height: parent.height
                    radius: 3
                    color: Properties.color

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
                            const ratio = mouse.x / width
                            root.localPosition = ratio * root.player.length
                            root.player.seek(root.localPosition)
                            root.seekPending = true
                        }
                    }
                }
            }
        }
    }
}
