import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

// Lyrics of the shown track (MediaLibrary.lyrics) in the music sheet.
// Synced: the line at the (extrapolated) position is lit and scrolled to the
// middle, smoothly; a click on a line seeks there (players that can seek).
// Scrolling by hand pauses the follow for a moment. Unsynced: plain text.
// No timer while paused or hidden: the next check is when the next line starts.
Item {
    id: root
    property var player: null
    property bool shown: false
    // the sheet's colour, for the soft fade at the top and bottom edge
    property color surface: Colors.surfacePopover

    readonly property var lyrics: MediaLibrary.lyrics
    readonly property bool ok: (lyrics?.status ?? "") === "ok"
    readonly property bool synced: ok && (lyrics?.synced ?? false)
    readonly property var lines: ok ? lyrics.lines : []
    property int current: -1

    // ── where we are ─────────────────────────────────────────────────────────
    function tick() {
        const s = root.player && typeof root.player.positionNow === "function" ? root.player.positionNow() : -1
        const ms = s < 0 ? -1 : s * 1000
        root.current = root.synced ? MediaLibrary.lineAt(ms) : -1
        // wake up when the next line starts (50 ms – 1 s)
        const next = root.lines[root.current + 1]
        clock.interval = root.synced && next && ms >= 0
            ? Math.max(50, Math.min(1000, (next.startMs - ms) / Math.max(0.25, root.player?.session?.playback?.rate ?? 1) + 15))
            : 1000
    }
    Timer {
        id: clock
        running: root.shown && root.synced && (root.player?.isPlaying ?? false)
        repeat: true
        onTriggered: root.tick()
    }
    onShownChanged: if (shown) { tick(); follow(false) }
    onLinesChanged: { scrollAnim.stop(); root.current = -1; view.contentY = 0; tick() }
    onCurrentChanged: follow(true)
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPbChanged() { root.tick() }          // seek, pause, play from anywhere
        function onIsPlayingChanged() { root.tick() }
    }
    onPlayerChanged: tick()

    // ── follow the current line ──────────────────────────────────────────────
    property real _holdUntil: 0
    function hold() { root._holdUntil = Date.now() + 2500; releaseHold.restart() }
    Timer { id: releaseHold; interval: 2600; onTriggered: root.follow(true) }

    function follow(animated) {
        if (!root.synced || !root.shown || Date.now() < root._holdUntil || view.moving) return
        const item = rep.itemAt(Math.max(0, root.current))
        if (!item) return
        const max = Math.max(0, view.contentHeight - view.height)
        const to = Math.max(0, Math.min(max, item.y + item.height / 2 - view.height * 0.42))
        scrollAnim.stop()
        if (!animated || !Anim.ambient) { view.contentY = to; return }
        scrollAnim.to = to
        scrollAnim.start()
    }
    NumberAnimation {
        id: scrollAnim
        target: view
        property: "contentY"
        duration: Anim.slower
        easing.type: Anim.emphasized
    }

    // ── states ───────────────────────────────────────────────────────────────
    // loading: only after a moment (cached lyrics come right away, no flash)
    property bool slow: false
    Timer { id: slowTimer; interval: 350; running: root.shown && root.lyrics === null; onTriggered: root.slow = true }
    onLyricsChanged: slow = false

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 260)
        visible: root.lyrics === null && root.slow
        compact: true
        loading: true
        text: "Looking for lyrics…"
    }
    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 260)
        visible: root.lyrics !== null && !root.ok
        compact: true
        icon: "󰍰"
        text: "No lyrics"
    }

    // ── the lines ────────────────────────────────────────────────────────────
    Flickable {
        id: view
        anchors.fill: parent
        visible: root.ok
        clip: true
        contentWidth: width
        contentHeight: col.height
        boundsBehavior: Flickable.StopAtBounds
        onMovementStarted: { scrollAnim.stop(); root.hold() }
        SmoothWheel { id: wheel; flick: view; step: 60 }
        Connections { target: wheel; function onWheel() { scrollAnim.stop(); root.hold() } }

        Column {
            id: col
            width: view.width
            // synced: room to bring the first and last line to the middle
            topPadding: root.synced ? view.height * 0.38 : Tokens.space.s12
            bottomPadding: root.synced ? view.height * 0.5 : Tokens.space.s16
            leftPadding: Tokens.space.s16
            rightPadding: Tokens.space.s16
            spacing: root.synced ? Tokens.space.s8 : Tokens.space.s4

            Repeater {
                id: rep
                model: root.lines
                Text {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property bool now: index === root.current
                    readonly property bool seekable: root.synced && (root.player?.canSeek ?? false)
                    width: col.width - col.leftPadding - col.rightPadding
                    // an empty line in LRC is an instrumental break
                    text: modelData.text.trim() !== "" ? modelData.text : (root.synced ? "♪" : " ")
                    wrapMode: Text.Wrap
                    color: now ? Colors.ink : Properties.color
                    font.pixelSize: root.synced ? Tokens.font.subtitle : Tokens.font.body
                    font.weight: root.synced ? Font.DemiBold : Font.Normal
                    font.family: Properties.fontFamily
                    lineHeight: 1.08
                    opacity: !root.synced ? 0.82
                           : now ? 1
                           : index < root.current ? 0.3 : 0.5
                    scale: now ? 1.045 : 1
                    transformOrigin: Item.Left
                    Behavior on opacity { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
                    Behavior on scale { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }

                    HoverHandler { enabled: line.seekable; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: line.seekable
                        onTapped: {
                            root.player.seek(line.modelData.startMs / 1000)
                            root._holdUntil = 0
                            root.current = line.index
                        }
                    }
                }
            }
        }
        ScrollBar.vertical: SlimScrollBar {}
    }

    // soft edges: lines fade in and out instead of being cut
    Rectangle {
        visible: view.visible && view.contentY > 1
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 28
        gradient: Gradient {
            GradientStop { position: 0; color: root.surface }
            GradientStop { position: 1; color: Colors.alpha(root.surface, 0) }
        }
    }
    Rectangle {
        visible: view.visible && view.contentY < view.contentHeight - view.height - 1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 34
        gradient: Gradient {
            GradientStop { position: 0; color: Colors.alpha(root.surface, 0) }
            GradientStop { position: 1; color: root.surface }
        }
    }

    // where they're from, and whether they follow the music
    Text {
        visible: root.ok
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: Tokens.space.s12; bottomMargin: Tokens.space.s6 }
        text: (root.synced ? "" : "not synced  ·  ")
            + (({ jellyfin: "Jellyfin", mpris: "from the player", lrclib: "LRCLIB" })[root.lyrics?.source ?? ""] ?? "")
        color: Colors.fade(0.35)
        font.pixelSize: Tokens.font.micro
        font.family: Properties.fontFamily
    }
}
