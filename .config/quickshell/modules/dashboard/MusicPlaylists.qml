import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.components

// Jellyfin playlists (MediaLibrary.playlists) in the music sheet: a click
// plays one on the shown session (play_items, "now"; mediasync keeps the
// playlist's order), the hover button adds it to the end of the queue.
// Only offered for sessions with "play_items".
Item {
    id: root
    property bool shown: false
    onShownChanged: if (shown) MediaLibrary.loadPlaylists(false)
    Connections {
        target: MediaLibrary
        function onServerChanged() { if (root.shown) MediaLibrary.loadPlaylists(false) }
    }

    readonly property var all: MediaLibrary.playlists
    readonly property string filter: search.text.trim().toLowerCase()
    readonly property var shownList: filter === "" ? all : all.filter(p => p.name.toLowerCase().includes(filter))

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.space.s6
        spacing: Tokens.space.s6

        // filter (only worth it for a longer list) + reload
        RowLayout {
            Layout.fillWidth: true
            visible: root.all.length > 6 || MediaLibrary.playlistsLoading
            spacing: Tokens.space.s6
            SearchField {
                id: search
                Layout.fillWidth: true
                implicitHeight: Tokens.size.controlSmall + 4
                placeholderText: "Filter playlists"
                visible: root.all.length > 6
            }
            Item { Layout.fillWidth: true; visible: !search.visible }
            IconButton {
                implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                iconSize: Tokens.icon.sm
                icon: "󰑐"
                tooltip: "Reload playlists"
                busy: MediaLibrary.playlistsLoading
                onClicked: MediaLibrary.loadPlaylists(true)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 280)
                visible: root.all.length === 0 && MediaLibrary.playlistsLoading
                compact: true
                loading: true
                text: "Loading playlists…"
            }
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 280)
                visible: root.all.length === 0 && !MediaLibrary.playlistsLoading && MediaLibrary.playlistsError !== ""
                compact: true
                icon: "󰌳"
                text: "Couldn't load the playlists"
                actionText: "Try again"
                onAction: MediaLibrary.loadPlaylists(true)
            }
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 280)
                visible: !MediaLibrary.playlistsLoading && MediaLibrary.playlistsError === ""
                         && root.shownList.length === 0 && (root.all.length > 0 || MediaLibrary.playlistsLoaded)
                compact: true
                icon: "󰌳"
                text: root.all.length > 0 ? "No playlist matches" : "No playlists on this server"
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: Tokens.space.s2
                boundsBehavior: Flickable.StopAtBounds
                model: root.shownList
                SmoothWheel { flick: list; step: 92 }
                ScrollBar.vertical: SlimScrollBar {}

                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool busy: MediaLibrary.playingPlaylist === modelData.id
                    readonly property bool done: MediaLibrary.playedPlaylist === modelData.id
                    readonly property bool free: MediaLibrary.playingPlaylist === ""
                    width: list.width
                    height: 46

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radius.lg
                        color: row.done ? Colors.alpha(Colors.accent, 0.16)
                             : hover.containsMouse ? Colors.fillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Anim.fast } }
                    }
                    // the row: under its contents, so the add button keeps its own click
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.free || row.busy
                        cursorShape: row.free ? Qt.PointingHandCursor : Qt.BusyCursor
                        onClicked: if (row.free) MediaLibrary.playPlaylist(row.modelData.id, "now")
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: Tokens.space.s6; rightMargin: Tokens.space.s8 }
                        spacing: Tokens.space.s10

                        ClippingRectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: Tokens.radius.md
                            color: Colors.fade(0.06)
                            Image {
                                id: art
                                anchors.fill: parent
                                source: MediaArt.get(row.modelData.art)
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 68
                                sourceSize.height: 68
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: art.status !== Image.Ready
                                text: "󰲸"
                                color: Colors.fade(0.35)
                                font.pixelSize: Tokens.font.subtitle
                                font.family: Properties.fontFamily
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                elide: Text.ElideRight
                                color: Properties.color
                                font.pixelSize: Tokens.font.small
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.done ? "Playing now"
                                    : row.modelData.count >= 0 ? row.modelData.count + (row.modelData.count === 1 ? " track" : " tracks") : " "
                                elide: Text.ElideRight
                                color: row.done ? Colors.accent : Colors.fade(0.45)
                                font.pixelSize: Tokens.font.caption
                                font.family: Properties.fontFamily
                            }
                        }

                        // add to the end of the queue (on hover)
                        IconButton {
                            implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall
                            iconSize: Tokens.icon.sm
                            icon: "󰐒"
                            tooltip: "Add to the queue"
                            opacity: (hover.containsMouse || hovered) && row.free ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Anim.fast } }
                            onClicked: MediaLibrary.playPlaylist(row.modelData.id, "last")
                        }
                        // play now; turns while the player confirms
                        Item {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Spinner {
                                anchors.centerIn: parent
                                visible: row.busy
                                running: row.busy
                                size: Tokens.font.label
                                color: Colors.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !row.busy
                                text: row.done ? "󰄳" : "󰐌"
                                color: row.done || hover.containsMouse ? Colors.accent : Colors.fade(0.3)
                                font.pixelSize: Tokens.font.title
                                font.family: Properties.fontFamily
                                Behavior on color { ColorAnimation { duration: Anim.fast } }
                            }
                        }
                    }

                }
            }
        }
    }
}
