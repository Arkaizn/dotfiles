import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 280)
        visible: root.q !== null && !root.available
        compact: true
        icon: "󰐑"
        text: "Queue not available for this player"
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Tokens.space.s6
        visible: root.available
        clip: true
        spacing: Tokens.space.s2
        boundsBehavior: Flickable.StopAtBounds
        model: root.available ? root.q.items : []
        SmoothWheel { flick: list; step: 84 }
        ScrollBar.vertical: SlimScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            required property int index
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
