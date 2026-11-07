import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// The music card's sheet: lyrics, queue, playlists or the player list, on a
// surface that unfolds from the card over the dashboard (into the free space
// below it, else above it, else over the whole column). Opened and closed
// by the card's buttons (DashboardMusic); `tab` "" = closed.
Rectangle {
    id: sheet
    required property Item host          // the dashboard's content: where it's drawn
    required property Item anchorItem    // the music card
    property string tab: ""
    property var tabs: []                // [{ value, label, icon }] the shown session offers
    property var player: null
    signal tabPicked(string tab)
    signal closeRequested()
    signal playerPicked(int index)

    parent: host
    z: 20

    // the last open tab stays while it folds away (no blank frame)
    property string shownTab: ""
    onTabChanged: if (tab !== "") { shownTab = tab; place() }
    // the playlist view asks the server: loaded once it's first wanted
    property bool _playlistsUsed: false
    onShownTabChanged: if (shownTab === "playlists") _playlistsUsed = true

    // ── where: the free space next to the card, in its column ─────────────────
    readonly property int gap: Tokens.space.s10
    readonly property int minHeight: 200
    property string dir: "down"          // down | up | over
    function place() {
        if (!host || !anchorItem) return
        const p = anchorItem.mapToItem(host, 0, 0)
        const below = host.height - (p.y + anchorItem.height) - gap
        const above = p.y - gap
        x = p.x
        width = anchorItem.width
        if (below >= minHeight) { dir = "down"; y = p.y + anchorItem.height + gap; height = below }
        else if (above >= minHeight) { dir = "up"; y = 0; height = above }
        else { dir = "over"; y = 0; height = host.height }
    }
    Connections {
        target: sheet.host
        function onWidthChanged() { if (sheet.tab !== "") sheet.place() }
        function onHeightChanged() { if (sheet.tab !== "") sheet.place() }
    }

    // ── look ─────────────────────────────────────────────────────────────────
    radius: Tokens.radius.card + 4
    // solid: the calendar underneath mustn't show through
    color: Qt.rgba(Colors.surfacePopover.r, Colors.surfacePopover.g, Colors.surfacePopover.b, 1)
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder

    // unfolds from the card's edge: slides out a little, fades and grows in
    property real amount: tab !== "" ? 1 : 0
    Behavior on amount { NumberAnimation { duration: sheet.tab !== "" ? Anim.medium : Anim.normal; easing.type: sheet.tab !== "" ? Anim.emphasized : Anim.exit } }
    visible: amount > 0
    opacity: amount
    transform: [
        Scale {
            origin.x: sheet.width / 2
            origin.y: sheet.dir === "up" ? sheet.height : 0
            xScale: 0.97 + 0.03 * sheet.amount
            yScale: 0.94 + 0.06 * sheet.amount
        },
        Translate { y: (1 - sheet.amount) * (sheet.dir === "up" ? 14 : -14) }
    ]

    // clicks don't fall through to the calendar underneath
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }

    Keys.onEscapePressed: sheet.closeRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.space.s8
        anchors.topMargin: Tokens.space.s6
        spacing: Tokens.space.s4

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space.s4
            spacing: Tokens.space.s8
            Segmented {
                variant: "tabs"
                options: sheet.tabs
                value: sheet.shownTab
                accessibleName: "Music sheet"
                onEdited: v => sheet.tabPicked(v)
            }
            Item { Layout.fillWidth: true }
            // what it's about: the sheet can hide the card when it opens over it
            Text {
                Layout.maximumWidth: sheet.width * 0.35
                visible: sheet.dir === "over" && (sheet.player?.trackTitle ?? "") !== ""
                text: sheet.player?.trackTitle ?? ""
                elide: Text.ElideRight
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }
            IconButton {
                implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                iconSize: Tokens.icon.sm
                icon: "󰅖"
                tooltip: "Close"
                onClicked: sheet.closeRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Properties.cardBorder
        }

        // the views stay loaded while the sheet is open: switching tabs keeps
        // the scroll position, and lyrics follow the music while hidden
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MusicLyrics {
                anchors.fill: parent
                visible: sheet.shownTab === "lyrics"
                shown: visible && sheet.visible
                player: sheet.player
                surface: sheet.color
            }
            MusicQueue {
                anchors.fill: parent
                visible: sheet.shownTab === "queue"
                shown: visible && sheet.visible
            }
            Loader {
                // asks the server for the list: only once it's wanted
                anchors.fill: parent
                active: sheet._playlistsUsed
                visible: sheet.shownTab === "playlists"
                sourceComponent: MusicPlaylists { shown: parent?.visible && sheet.visible }
            }
            MusicPlayers {
                anchors.fill: parent
                visible: sheet.shownTab === "players"
                current: sheet.player
                onPicked: i => sheet.playerPicked(i)
            }
        }
    }
}
