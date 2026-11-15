import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// The offline game's card: a small pixel runner at the top of the control center
// while nothing is connected and the bar's offline icon was clicked
// (services/OfflineGame.qml). A little dino runs (or another pet, a setting),
// dead network gear comes at it: routers, switches, stacks of them, server racks;
// Space, ↑ or a click jumps. The rules are services/lib/Runner.js; this draws
// what its state says, in the scheme's colours.
//
// It never gets in the way of reconnecting: the Wi-Fi list is open right
// below, ✕ folds the card away, and when the connection is back the run ends
// by itself ("Back online") and the card goes.
Card {
    id: root

    property real gap: 0                   // the spacing of the column it sits in (folded away with it)
    readonly property bool playing: phase === "run"

    // ── shown / folded away ──
    property bool ending: false            // back online: stays for the goodbye
    readonly property bool shown: (OfflineGame.wanted && OfflineGame.enabled) || ending
    property real amount: shown ? 1 : 0
    Behavior on amount { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    visible: amount > 0
    opacity: amount
    clip: true
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight * amount
    Layout.bottomMargin: -gap * (1 - amount)
    implicitHeight: col.implicitHeight + Tokens.space.s12 * 2

    // ── the game ──
    readonly property int px: 2            // screen pixels per art pixel
    readonly property var runner: OfflineGame.runner
    readonly property int fieldH: 46 + runner.h + groundH      // jump height + the runner + the ground
    readonly property int groundH: 5
    readonly property int fieldW: Math.max(80, Math.floor(field.width / px))
    // what's in the way, one picked at random each time: router, switch, a stack of switches, a server rack
    readonly property var kinds: PixelBits.obstacles.map(k => ({ kind: k, w: PixelBits.size(k).w, h: PixelBits.size(k).h }))
    // the world in the scheme's colours; the runner too (its coat is for the desktop)
    readonly property var colors: ({ ink: Colors.ink, accent: Colors.accent, muted: Colors.fade(0.3), soft: Colors.fade(0.6),
                                     red: Colors.red, hole: Colors.background })
    // line art: its outline in ink, hollow inside, the small things in the accent colour
    readonly property var runnerPalette: ({ k: "ink", o: "hole", h: "hole", s: "hole", w: "hole", d: "accent", p: "accent", b: "accent", e: "ink", i: "hole" })

    property var s: null                   // Runner state
    property string phase: "ready"
    property real jumpY: 0
    property real dist: 0
    property real speed: 0
    property int score: 0
    property var obs: []
    property real clock: 0                 // seconds played, for the running legs
    property bool canRestart: false
    property bool newBest: false

    function reset() {
        s = Runner.create(fieldW, runner.w, runner.h)
        newBest = false
        clock = 0
        sync()
    }
    function sync() {
        const was = phase
        phase = s.phase
        jumpY = s.y
        dist = s.dist
        speed = s.speed
        score = s.score
        obs = s.obstacles.map(o => ({ x: o.x, h: o.h, kind: o.kind }))
        canRestart = s.phase === "over" && s.stop >= 0.5
        if (was === "run" && phase === "over") newBest = OfflineGame.submit(score)
    }
    function act() {
        field.forceActiveFocus()
        if (!s || ending) return
        if (Runner.press(s) === "start") { newBest = false; clock = 0 }
        sync()
    }
    onShownChanged: if (shown && !ending) reset()
    onFieldWChanged: if (s) s.w = fieldW
    onRunnerChanged: if (shown && !ending) reset()

    // the connection is back
    Connections {
        target: OfflineGame
        function onOfflineChanged() {
            if (OfflineGame.offline || !root.shown || root.ending) return
            root.ending = true
            if (root.s) { Runner.online(root.s); root.sync() }
            bye.restart()
        }
    }
    Timer {
        id: bye
        interval: 3200
        onTriggered: { OfflineGame.wanted = false; root.ending = false }
    }

    FrameAnimation {
        running: root.visible && root.s !== null
                 && (root.phase === "run" || (root.phase === "online" && root.speed > 0) || (root.phase === "over" && !root.canRestart))
        onTriggered: {
            root.clock += frameTime
            Runner.step(root.s, frameTime, root.kinds, Math.random)
            root.sync()
        }
    }

    readonly property string runnerFrame: phase === "over" ? PixelArt.frameAt(runner, "hit", 0)
        : phase === "ready" ? PixelArt.frameAt(runner, "stand", 0)
        : phase === "online" && speed === 0 ? PixelArt.frameAt(runner, "sit", 0)
        : jumpY > 0 ? PixelArt.frameAt(runner, "jump", 0)
        : PixelArt.frameAt(runner, "run", clock * 1000)

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.s12 }
        spacing: Tokens.space.s8

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Text {
                text: Icons.get("offline")
                color: Colors.textSecondary
                font { pixelSize: Tokens.font.label; family: Properties.fontFamily }
            }
            Text {
                Layout.fillWidth: true
                text: root.ending ? "Back online" : "No connection"
                elide: Text.ElideRight
                color: Colors.textStrong
                font { pixelSize: Tokens.font.small; bold: true; family: Properties.fontFamily }
            }
            Text {
                visible: OfflineGame.best > 0
                text: "Best " + OfflineGame.best
                color: root.newBest ? Colors.accent : Colors.textMuted
                font { pixelSize: Tokens.font.caption; family: Properties.fontFamily; features: Tokens.font.tnum }
            }
            Text {
                text: String(root.score).padStart(5, "0")
                color: Colors.textStrong
                font { pixelSize: Tokens.font.small; bold: true; family: Properties.fontFamily; features: Tokens.font.tnum }
            }
            IconButton {
                implicitWidth: Tokens.size.controlSmall
                implicitHeight: Tokens.size.controlSmall
                iconSize: Tokens.icon.sm
                icon: "󰅖"
                tooltip: "Close the game"
                onClicked: OfflineGame.wanted = false
            }
        }

        Item {
            id: field
            Layout.fillWidth: true
            implicitHeight: root.fieldH * root.px
            clip: true
            focus: true
            Keys.onPressed: e => {
                if ((e.key === Qt.Key_Space || e.key === Qt.Key_Up) && !e.isAutoRepeat) { root.act(); e.accepted = true }
            }

            readonly property real floor: height - root.groundH * root.px      // where feet stand

            // clouds, far away: they drift at a fifth of the speed
            Repeater {
                model: 2
                PixelSprite {
                    required property int index
                    rows: PixelBits.def.parts.cloud
                    palette: PixelBits.def.palette
                    colors: root.colors
                    px: root.px
                    readonly property real lane: root.fieldW + artWidth
                    readonly property real at: (((index * 0.55 + 0.3) * lane - root.dist * 0.2) % lane + lane) % lane
                    x: Math.round(at - artWidth) * root.px
                    y: (4 + index * 9) * root.px
                }
            }

            // the ground: a line, and specks that run past
            Rectangle {
                anchors { left: parent.left; right: parent.right }
                y: field.floor
                height: root.px
                color: Colors.fade(0.6)
            }
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    readonly property real lane: root.fieldW + 8
                    readonly property real at: (((index * 0.137 + 0.05) * lane * 1.9 - root.dist) % lane + lane) % lane
                    x: Math.round(at - 4) * root.px
                    y: field.floor + (2 + index % 2) * root.px
                    width: (2 + index % 3) * root.px
                    height: root.px
                    color: Colors.fade(0.3)
                }
            }

            // what's in the way (never more than a few at once)
            Repeater {
                model: 5
                PixelSprite {
                    required property int index
                    readonly property var o: root.obs[index] ?? null
                    visible: o !== null
                    rows: o ? PixelBits.def.parts[o.kind] : []
                    palette: PixelBits.def.palette
                    colors: root.colors
                    px: root.px
                    x: Math.round(o?.x ?? 0) * root.px
                    y: field.floor - height
                }
            }

            PixelSprite {
                rows: PixelArt.frame(root.runner, root.runnerFrame)
                palette: root.runnerPalette
                colors: root.colors
                px: root.px
                x: (root.s?.runner.x ?? 10) * root.px
                y: field.floor - height - Math.round(root.jumpY) * root.px
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // under the clouds
                y: 22 * root.px
                horizontalAlignment: Text.AlignHCenter
                visible: opacity > 0
                opacity: root.phase === "run" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                text: root.ending ? "You're connected again"
                    : root.phase === "over" ? (root.newBest ? "New best: " + root.score : "Tripped at " + root.score) + "\nSpace or click to run again"
                    : "Space or click to jump"
                color: root.ending ? Colors.accent : Colors.textSecondary
                lineHeight: 1.3
                font { pixelSize: Tokens.font.small; family: Properties.fontFamily; features: Tokens.font.tnum }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.act()
            }
        }
    }
}
