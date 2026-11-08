import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.services.lib
import qs.components

// The shown session's queue (MediaLibrary.queue) in the music sheet: the
// playing track lit, a click jumps there (only sessions with "queue_jump").
// Jellyfin 12.x shows no queue during playback, so "not available" is a calm,
// normal state here, not an error.
Item {
    id: root
    property bool shown: false

    readonly property var q: MediaLibrary.queue
    readonly property bool available: q?.available ?? false
    readonly property int current: MediaLibrary.pendingJump >= 0 ? MediaLibrary.pendingJump : (q?.currentIndex ?? -1)

    // the playing track in view when it opens or the queue changes
    function center() {
        if (!root.shown || !root.available || root.current < 0) return
        list.positionViewAtIndex(Math.max(0, root.q.items.findIndex(i => i.index === root.current)), ListView.Center)
    }
    onShownChanged: Qt.callLater(center)
    onQChanged: { slow = false; Qt.callLater(center) }

    property bool slow: false
    Timer { interval: 350; running: root.shown && root.q === null; onTriggered: root.slow = true }

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 280)
        visible: root.q === null && root.slow
        compact: true
        loading: true
        text: "Loading the queue…"
    }
    EmptyState {
        // under the playlist card when there is one
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: fromCard.visible ? fromCard.height / 2 : 0
        width: Math.min(parent.width - 40, 280)
        visible: root.q !== null && !root.available
        compact: true
        icon: "󰐑"
        text: root.context !== null ? (root.context.shuffled ? "Shuffled: the order shows once the player reports it"
                                                             : "The track list shows once the player reports it")
                                    : "Queue not available for this player"
    }

    // where the queue comes from: only known when mediasync started it (a
    // playlist / album from the dashboard); the list is then the whole of it,
    // played tracks included, and a jump keeps it (mediasync sends it again)
    readonly property var context: MediaLibrary.context
    readonly property bool busy: root.context !== null && MediaLibrary.playingPlaylist === root.context.id
    Rectangle {
        id: fromCard
        visible: root.context !== null
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.s6 }
        height: visible ? 56 : 0
        radius: Tokens.radius.lg
        color: Colors.fade(0.05)
        border.width: Tokens.border.thin
        border.color: Colors.fade(0.08)

        RowLayout {
            anchors { fill: parent; leftMargin: Tokens.space.s8; rightMargin: Tokens.space.s8 }
            spacing: Tokens.space.s10

            ClippingRectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Tokens.radius.md
                color: Colors.fade(0.06)
                Image {
                    id: ctxArt
                    anchors.fill: parent
                    source: MediaLibrary.contextArt
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 80
                    sourceSize.height: 80
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: ctxArt.status !== Image.Ready
                    text: root.context?.type === "album" ? "󰀥" : "󰲸"
                    color: Colors.fade(0.4)
                    font.pixelSize: Tokens.font.subtitle
                    font.family: Properties.fontFamily
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Text {
                    text: (root.context?.type === "album" ? "ALBUM" : "PLAYLIST") + (root.context?.shuffled ? "  ·  SHUFFLED" : "")
                    color: Colors.fade(0.4)
                    font.pixelSize: Tokens.font.micro
                    font.bold: true
                    font.letterSpacing: 1
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.context?.name || "Untitled"
                    elide: Text.ElideRight
                    color: Colors.ink
                    font.pixelSize: Tokens.font.body
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    // the list's length, else (not reported yet) the playlist's own count
                    readonly property int n: (root.q?.items?.length ?? 0) > 0 ? root.q.items.length
                        : (MediaLibrary.playlists.find(p => p.id === root.context?.id)?.count ?? -1)
                    visible: n >= 0
                    text: n + (n === 1 ? " track" : " tracks")
                    color: Colors.fade(0.45)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
            }

            // from the start · shuffled (the whole playlist / album again)
            IconButton {
                visible: MediaLibrary.playlistsShown
                implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                iconSize: Tokens.icon.sm
                icon: root.busy ? "󰑓" : "󰐊"
                busy: root.busy
                tooltip: "Play from the start"
                onClicked: MediaLibrary.playPlaylist(root.context.id, "now", false)
            }
            IconButton {
                visible: MediaLibrary.shuffleShown
                implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                iconSize: Tokens.icon.sm
                icon: "󰒝"
                tooltip: "Shuffle play"
                enabled: !root.busy
                onClicked: MediaLibrary.playPlaylist(root.context.id, "now", true)
            }
        }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: fromCard.visible ? fromCard.bottom : parent.top }
        anchors.margins: Tokens.space.s6
        visible: root.available
        clip: true
        spacing: Tokens.space.s2
        boundsBehavior: Flickable.StopAtBounds
        model: root.available ? root.q.items : []
        SmoothWheel { flick: list; step: 84 }
        ScrollBar.vertical: SlimScrollBar {}

        delegate: Column {
            id: entry
            required property var modelData
            required property int index
            width: list.width
            // "Played" above the first track when some were, "Up next" after the playing one
            readonly property string label: entry.index === 0 && root.current > 0 ? "Played"
                                          : root.current >= 0 && entry.modelData.index === root.current + 1 ? "Up next" : ""
            Text {
                visible: entry.label !== ""
                height: visible ? 24 : 0
                leftPadding: Tokens.space.s10
                topPadding: entry.index === 0 ? 2 : Tokens.space.s8
                text: entry.label.toUpperCase()
                color: Colors.fade(0.4)
                font.pixelSize: Tokens.font.micro
                font.bold: true
                font.letterSpacing: 1.2
                font.family: Properties.fontFamily
            }
        Item {
            id: row
            readonly property var modelData: entry.modelData
            readonly property bool playing: modelData.index === root.current
            readonly property bool past: root.current >= 0 && modelData.index < root.current
            readonly property bool jumpable: MediaLibrary.canJump && !playing
            width: list.width
            height: 40

            Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.lg
                color: row.playing ? Colors.alpha(Colors.accent, 0.16)
                     : hover.hovered && row.jumpable ? Colors.fillHover : "transparent"
                border.width: row.playing ? Tokens.border.thin : 0
                border.color: Colors.alpha(Colors.accent, 0.4)
                Behavior on color { ColorAnimation { duration: Anim.fast } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Tokens.space.s10; rightMargin: Tokens.space.s12 }
                spacing: Tokens.space.s10

                // number, or what's playing (a spinner while the jump runs)
                Item {
                    Layout.preferredWidth: 22
                    Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent
                        visible: !row.playing
                        text: row.modelData.index + 1
                        color: Colors.fade(0.35)
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                        font.features: { "tnum": 1 }
                    }
                    Spinner {
                        anchors.centerIn: parent
                        visible: row.playing && MediaLibrary.pendingJump === row.modelData.index
                        running: visible
                        size: Tokens.font.body
                        color: Colors.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: row.playing && MediaLibrary.pendingJump !== row.modelData.index
                        text: "󰎇"
                        color: Colors.accent
                        font.pixelSize: Tokens.font.label
                        font.family: Properties.fontFamily
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        elide: Text.ElideRight
                        color: row.playing ? Colors.ink : Properties.color
                        opacity: row.past ? 0.55 : 1
                        font.pixelSize: Tokens.font.small
                        font.bold: row.playing
                        font.family: Properties.fontFamily
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: [row.modelData.artist, row.modelData.album].filter(x => x).join("  ·  ")
                        elide: Text.ElideRight
                        color: Colors.fade(row.past ? 0.3 : 0.45)
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    text: MediaSources.clock(row.modelData.durationMs)
                    color: Colors.fade(0.35)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    font.features: { "tnum": 1 }
                }
            }

            HoverHandler { id: hover; cursorShape: row.jumpable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler {
                enabled: row.jumpable && MediaLibrary.pendingJump < 0
                onTapped: MediaLibrary.jump(row.modelData.index)
            }
        }
        }
    }
}
