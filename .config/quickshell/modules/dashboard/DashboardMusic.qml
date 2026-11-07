import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.services
import qs.services.lib
import qs.components

Item {
    id: root
    anchors.fill: parent

    // set by the dashboard: true while it's open (position polling only then)
    property bool active: false
    // the dashboard's content item: the sheet (lyrics, queue, …) is drawn there
    property Item sheetHost: null

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

    // position: native players' own, bridge sessions extrapolated from
    // position_ms / position_at (MediaSource.positionNow); -1 = unknown (a
    // stale session): no time, no progress then, nothing faked
    function syncPosition() {
        // (a source that's just going away can still send a last change)
        if (!root.player || typeof root.player.positionNow !== "function") return
        if (seekPending) {
            seekPending = false
            return
        }
        const p = root.player.positionNow()
        root.positionKnown = p >= 0
        localPosition = Math.max(0, p)
        // the next tick right after the next full second: the time label counts evenly
        positionTimer.interval = p >= 0 ? 1000 - Math.floor((p * 1000) % 1000) + 15 : 1000
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPbChanged() { root.syncPosition() }          // paused, seeked, … anywhere
        function onIsPlayingChanged() { root.syncPosition() }
    }

    // ── Sheet: lyrics / queue / playlists / players ──────────────────────────
    // "" = closed. The buttons in the card toggle it; only what the shown
    // session offers is there (MediaLibrary.*Shown).
    property string sheetTab: ""
    readonly property bool canSwitch: root.players.length > 1
    // players first: it doesn't depend on the session, so it keeps its place
    // (top of the rail, leftmost tab) while the others come and go
    readonly property var sheetTabs: [
        root.canSwitch ? { value: "players", label: "Players", icon: "󰄘" } : null,
        MediaLibrary.lyricsShown ? { value: "lyrics", label: "Lyrics", icon: "󰍰" } : null,
        MediaLibrary.queueShown ? { value: "queue", label: "Queue", icon: "󰐑" } : null,
        MediaLibrary.playlistsShown ? { value: "playlists", label: "Playlists", icon: "󰌳" } : null
    ].filter(t => t !== null)
    function toggleSheet(tab) { root.sheetTab = root.sheetTab === tab ? "" : tab }
    // the session changed and doesn't offer that view: the next one it has, else closed
    onSheetTabsChanged: if (sheetTab !== "" && !sheetTabs.some(t => t.value === sheetTab)) sheetTabFix.restart()
    Timer {
        id: sheetTabFix
        interval: 400           // a session switch passes through "no session" for a moment
        onTriggered: if (root.sheetTab !== "" && !root.sheetTabs.some(t => t.value === root.sheetTab))
                         root.sheetTab = root.sheetTabs[0]?.value ?? ""
    }
    onActiveChanged: {
        if (active) MediaLibrary.acquire()
        else { MediaLibrary.release(); root.sheetTab = "" }      // closed with the dashboard
    }
    Component.onCompleted: if (active) MediaLibrary.acquire()
    Component.onDestruction: if (active) MediaLibrary.release()
    Connections {
        target: EditMode
        function onTargetChanged() { if (EditMode.target === "dashboard") root.sheetTab = "" }
    }

    function pickPlayer(i) {
        const src = root.players[i]
        if (!src) return
        root.localPosition = 0
        root.errorText = ""
        if (Media.bridgeActive) MediaSync.select(src.sessionId)
        else root.currentPlayerIndex = i
        playerSwitchSync.restart()
    }

    // which controls this session has (bridge sessions: only what they advertise)
    readonly property bool showShuffle: player?.canShuffle ?? false
    readonly property bool showLoop: player?.canLoop ?? false
    readonly property bool showPrev: player?.canGoPrevious ?? false
    readonly property bool showNext: player?.canGoNext ?? false
    readonly property bool showPlay: !!player && (player.mpris ? player.canControl && (player.canPlay || player.canPause || player.canTogglePlaying)
                                                              : (player.canTogglePlaying || player.canPlay || player.canPause))
    readonly property bool anyControl: showShuffle || showLoop || showPrev || showNext || showPlay
    // marks: view only / not reporting / server unreachable
    readonly property string kindNote: !player ? ""
        : player.kind === "disconnected" ? "server unreachable"
        : player.kind === "stale" || player.stale ? "not reporting"
        : player.viewOnly ? "view only" : ""

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
        // it's blurred with radius 72: a small decode looks the same and keeps
        // the track change (synchronous, so no blank frame) and the blur cheap
        sourceSize.width: 128
        sourceSize.height: 128
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
            color: Colors.dim(0.5)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.dim(0.3)
        visible: bgArt.source === "" || bgArt.status !== Image.Ready
        radius: root.parent ? (root.parent.radius ?? 12) : 12
    }

    // ── Position polling ─────────────────────────────────────────────────────
    // (local: nothing is asked from the bridge, positions are extrapolated)
    Timer {
        id: positionTimer
        interval: 1000
        running: root.active && root.player !== null && root.player.isPlaying
        repeat: true
        triggeredOnStart: true      // up to date as soon as the dashboard opens
        onTriggered: root.syncPosition()
    }

    // ── No player state ──────────────────────────────────────────────────────
    EmptyState {
        anchors.centerIn: parent
        visible: root.player === null
        compact: true
        icon: "󰝛"
        text: "No media playing"
    }

    // ── Main layout ──────────────────────────────────────────────────────────
    RowLayout {
        anchors {
            fill: parent
            margins: Tokens.space.s12
        }
        spacing: Tokens.space.s12
        visible: root.player !== null

        // Album art
        Rectangle {
            id: artBox
            width: 130
            height: 130
            radius: Tokens.radius.dialog
            color: Colors.fade(0.06)
            clip: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: 130
                    height: 130
                    radius: Tokens.radius.dialog
                }
            }

            Image {
                id: albumArtImage
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                // decoded at twice the card's size, not the art's (remote art can be 1280 px+)
                sourceSize.width: 320
                sourceSize.height: 320
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

            // view only / not reporting / server unreachable: marked on the cover
            Rectangle {
                visible: root.kindNote !== ""
                anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                implicitHeight: 20
                implicitWidth: kindRow.implicitWidth + 12
                radius: Tokens.radius.md
                color: Colors.dim(0.6)
                Row {
                    id: kindRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.kindNote === "view only" ? "󰈈" : "󰅤"
                        color: "white"
                        opacity: 0.8
                        font.pixelSize: Tokens.font.caption
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.kindNote
                        color: "white"
                        opacity: 0.85
                        font.pixelSize: Tokens.font.micro
                        font.bold: true
                    }
                }
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
                width: volLabel.implicitWidth + 18; height: 26; radius: Tokens.radius.md
                color: Colors.dim(0.55)
                opacity: volumeShow.running ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Anim.normal } }
                Text {
                    id: volLabel
                    anchors.centerIn: parent
                    text: "󰕾  " + Math.round(artBox.shownVolume * 100) + "%"
                    color: "white"
                    font.pixelSize: Tokens.font.small
                    font.bold: true
                }
            }
        }

        // Right side (takes what's left: long titles / notes elide, never push the rail out)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            spacing: 5

            // Track title + artist
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Tokens.space.s2

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
                    font.pixelSize: Tokens.font.small
                    elide: Text.ElideRight
                }
            }

            // source pill (switches player) + jump to the player
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: Tokens.space.s6

            Rectangle {
                id: sourcePill
                Layout.alignment: Qt.AlignLeft
                // implicit size: the row lays it out to fit the icon + player name
                implicitHeight: 26
                implicitWidth: pillRow.implicitWidth + 18
                radius: Tokens.radius.md
                border.color: Colors.fade(sourceHover.containsMouse ? 0.28 : 0.18)
                border.width: 0.5
                gradient: ButtonGradient { hovered: sourceHover.containsMouse }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                    radius: Tokens.radius.md; color: Colors.dim(0.1)
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
                        font.pixelSize: Tokens.font.small
                        color: root.player?.remote ? Colors.color6 : Properties.color
                        visible: appIcon.status !== Image.Ready
                    }

                    Text {
                        id: sourceLabel
                        Layout.maximumWidth: 84
                        elide: Text.ElideRight
                        text: !root.player ? "No player" : (root.player.identity || "Player")
                        color: Properties.color
                        font.pixelSize: Tokens.font.caption
                        font.bold: true
                    }
                    // where it plays: the phone (or another remote device) or this PC
                    Text {
                        visible: root.player !== null
                        text: "·"
                        color: Colors.fade(0.35)
                        font.pixelSize: Tokens.font.caption
                    }
                    Text {
                        visible: root.player !== null
                        text: root.player?.deviceKind === "phone" ? "󰄜" : "󰍹"
                        color: root.player?.remote ? Colors.color6 : Colors.fade(0.6)
                        font.pixelSize: Tokens.font.caption
                    }
                    Text {
                        visible: root.player !== null
                        Layout.maximumWidth: 92
                        elide: Text.ElideRight
                        text: root.player?.deviceName ?? ""
                        color: root.player?.remote ? Colors.color6 : Colors.fade(0.6)
                        font.pixelSize: Tokens.font.caption
                        font.bold: root.player?.remote ?? false
                    }
                    // more players: this opens the list
                    Text {
                        visible: root.canSwitch
                        text: "󰅀"
                        color: Colors.fade(0.5)
                        font.pixelSize: Tokens.font.caption
                    }
                }

                Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
                // click: the player list (with more than one) · right click: the next player
                MouseArea {
                    id: sourceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.canSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: if (root.canSwitch) sourcePill.scale = 1.05
                    onExited:  sourcePill.scale = 1.0
                    onPressed: if (root.canSwitch) sourcePill.scale = Properties.onPressedButtonScale
                    onReleased: sourcePill.scale = containsMouse && root.canSwitch ? 1.05 : 1.0
                    onCanceled: sourcePill.scale = 1.0
                    onClicked: m => {
                        if (m.button === Qt.RightButton) root.nextPlayer()
                        else if (root.canSwitch) root.toggleSheet("players")
                    }
                }
            }

            // jump to the player: its window (and in a browser the playing tab)
            Rectangle {
                id: jumpBtn
                visible: root.player !== null && !root.player.remote
                implicitWidth: 26; implicitHeight: 26
                radius: Tokens.radius.md
                border.color: Colors.fade(jumpHover.containsMouse ? 0.28 : 0.18)
                border.width: 0.5
                gradient: ButtonGradient { hovered: jumpHover.containsMouse }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                    radius: Tokens.radius.md; color: Colors.dim(0.1)
                }
                Text {
                    anchors.centerIn: parent
                    text: "󰏌"
                    font.pixelSize: Tokens.font.body
                    color: Properties.color
                }
                Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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

            // the bridge is on in settings but not reachable right now
            Text {
                visible: root.bridgeOffline
                text: "mediasync offline"
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.micro
                font.italic: true
            }
            }

            // fixed gap: the controls sit at the same place whatever is shown above
            Item { Layout.preferredHeight: 6 }

            // Controls row — shuffle / prev / play / next / repeat
            RowLayout {
                Layout.fillWidth: true
                transform: Translate { y: -4 }      // a touch higher, with the bar below
                spacing: Tokens.space.s4

                Item { Layout.fillWidth: true }

                // nothing to control: say why instead of an empty row
                Text {
                    visible: root.player !== null && !root.anyControl
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 34
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.kindNote === "server unreachable" ? "Server unreachable · last known state"
                        : root.kindNote === "not reporting" ? "Not reporting · last known state"
                        : "Can't be controlled from here"
                    color: Colors.fade(0.4)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }

                // ── Shuffle ──────────────────────────────────────────────────
                Rectangle {
                    visible: root.showShuffle
                    width: 34
                    height: 34
                    radius: Tokens.radius.md
                    border.color: Colors.fade(shuffleHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: shuffleHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: Tokens.radius.md; color: Colors.dim(0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒝"
                        font.pixelSize: 15
                        // Active = Colors.color6, inactive = dim white
                        color: root.player && root.player.shuffle
                               ? Colors.color6 : Colors.fade(0.35)
                    }
                    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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
                    visible: root.showPrev
                    width: 34; height: 34; radius: Tokens.radius.md
                    border.color: Colors.fade(prevHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: prevHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: Tokens.radius.md; color: Colors.dim(0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        font.pixelSize: Tokens.font.title
                        color: root.player && root.player.canGoPrevious
                               ? Properties.color : Colors.fade(0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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
                    visible: root.showPlay
                    width: 34; height: 34; radius: Tokens.radius.md
                    border.color: Colors.fade(playHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: playHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: Tokens.radius.md; color: Colors.dim(0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                        font.pixelSize: Tokens.font.titleLarge
                        color: !root.player || root.player.mpris || root.player.canTogglePlaying
                               ? Properties.color : Colors.fade(0.25)
                        // a remote command waits for the phone to confirm (up to a few seconds)
                        opacity: root.player?.busy ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: Anim.normal } }
                    }
                    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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
                    visible: root.showNext
                    width: 34; height: 34; radius: Tokens.radius.md
                    border.color: Colors.fade(nextHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: nextHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: Tokens.radius.md; color: Colors.dim(0.1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        font.pixelSize: Tokens.font.title
                        color: root.player && root.player.canGoNext
                               ? Properties.color : Colors.fade(0.25)
                    }
                    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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
                    visible: root.showLoop
                    width: 34; height: 34; radius: Tokens.radius.md
                    border.color: Colors.fade(repeatHover.containsMouse ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: repeatHover.containsMouse }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 0.8; anchors.topMargin: 1.5
                        radius: Tokens.radius.md; color: Colors.dim(0.1)
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
                    }
                    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
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

            // elapsed time (styled like the dashboard's date line) + progress bar
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s8

            Text {
                id: elapsedLabel
                visible: root.player !== null && root.positionKnown
                text: MediaSources.clock(root.localPosition * 1000)
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                font.features: { "tnum": 1 }        // the digits don't jiggle as they count
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 5

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
                    anchors.topMargin: -6       // easier to hit than 5 px
                    anchors.bottomMargin: -6
                    cursorShape: root.player?.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: (mouse) => {
                        if (root.player && root.player.canSeek && root.player.lengthSupported) {
                            const ratio = Math.max(0, Math.min(1, mouse.x / width))
                            root.localPosition = ratio * root.player.length
                            root.positionKnown = true
                            root.player.seek(root.localPosition)
                            root.seekPending = true
                        }
                    }
                }
            }
            }
        }

        // the sheet's buttons: a slim rail on the right (each lights while its view is open)
        ColumnLayout {
            visible: root.sheetTabs.length > 0
            Layout.fillHeight: true
            Layout.preferredWidth: Tokens.size.controlSmall
            spacing: Tokens.space.s6
            Repeater {
                model: root.sheetTabs
                IconButton {
                    required property var modelData
                    implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                    iconSize: Tokens.icon.md
                    icon: modelData.icon
                    active: root.sheetTab === modelData.value
                    textColor: active ? Colors.accent : Properties.color
                    tooltip: (active ? "Hide " : "Show ") + modelData.label.toLowerCase()
                    onClicked: root.toggleSheet(modelData.value)
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── the sheet (lyrics / queue / playlists / players) ─────────────────────
    MusicSheet {
        host: root.sheetHost ?? root
        anchorItem: root
        tab: root.sheetHost !== null && root.player !== null ? root.sheetTab : ""
        tabs: root.sheetTabs
        player: root.player
        onTabPicked: t => root.sheetTab = t
        onCloseRequested: root.sheetTab = ""
        onPlayerPicked: i => root.pickPlayer(i)
    }
}
