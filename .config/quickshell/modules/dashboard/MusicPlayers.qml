import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.components

// Every media session (Media.sources) in the music sheet: where it plays, what,
// and whether it can be controlled. A click shows that one (with the bridge:
// sessions.select, so the bar follows; without it: the card's own pick).
Item {
    id: root
    property var current: null          // the source the card shows
    signal picked(int index)

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Tokens.space.s6
        clip: true
        spacing: Tokens.space.s2
        boundsBehavior: Flickable.StopAtBounds
        model: Media.sources
        SmoothWheel { flick: list; step: 100 }
        ScrollBar.vertical: SlimScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var src: modelData
            readonly property bool selected: src === root.current
            readonly property string note: src.kind === "disconnected" ? "server unreachable"
                                         : src.kind === "stale" || src.stale ? "not reporting"
                                         : src.viewOnly ? "view only" : ""
            width: list.width
            height: 50

            Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.lg
                color: row.selected ? Colors.alpha(Colors.accent, 0.16) : hover.hovered ? Colors.fillHover : "transparent"
                border.width: row.selected ? Tokens.border.thin : 0
                border.color: Colors.alpha(Colors.accent, 0.4)
                Behavior on color { ColorAnimation { duration: Anim.fast } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Tokens.space.s6; rightMargin: Tokens.space.s12 }
                spacing: Tokens.space.s10

                // cover, with where it plays on it
                Item {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: Colors.fade(0.06)
                        Image {
                            id: art
                            anchors.fill: parent
                            source: row.src.trackArtUrl
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 76
                            sourceSize.height: 76
                            asynchronous: true
                            visible: status === Image.Ready
                            opacity: row.src.stale ? 0.5 : 1
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: art.status !== Image.Ready
                            text: "󰎇"
                            color: Colors.fade(0.35)
                            font.pixelSize: Tokens.font.subtitle
                            font.family: Properties.fontFamily
                        }
                    }
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -3; bottomMargin: -3 }
                        width: 17; height: 17; radius: 9
                        color: row.src.remote ? Colors.color6 : Colors.surfacePopover
                        border.width: Tokens.border.thin
                        border.color: Colors.surfacePopover
                        Text {
                            anchors.centerIn: parent
                            text: row.src.deviceKind === "phone" ? "󰄜" : "󰍹"
                            color: row.src.remote ? Colors.background : Properties.color
                            font.pixelSize: Tokens.font.micro
                            font.family: Properties.fontFamily
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space.s6
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: row.src.identity + "  ·  " + row.src.deviceName
                            elide: Text.ElideRight
                            color: row.selected ? Colors.ink : Properties.color
                            font.pixelSize: Tokens.font.small
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                        Text {
                            visible: row.note !== ""
                            text: row.note
                            color: Colors.fade(0.45)
                            font.pixelSize: Tokens.font.micro
                            font.italic: true
                            font.family: Properties.fontFamily
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [row.src.trackTitle, row.src.trackArtist].filter(x => x).join("  —  ") || "Nothing playing"
                        elide: Text.ElideRight
                        color: Colors.fade(0.5)
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    text: row.src.isPlaying ? "󰐊" : "󰏤"
                    color: row.src.isPlaying ? Colors.accent : Colors.fade(0.3)
                    font.pixelSize: Tokens.font.label
                    font.family: Properties.fontFamily
                }
            }

            HoverHandler { id: hover; cursorShape: row.selected ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler {
                enabled: !row.selected
                onTapped: root.picked(row.index)
            }
        }
    }
}
