import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

// Notifications on the lockscreen: newest app groups first, each showing
// the latest message. New ones slide in while locked (the normal popups
// can't show above the lock).
ColumnLayout {
    id: root

    readonly property int maxGroups: 5
    // private: only the app and how many, no text (Settings → Lockscreen)
    property bool privateMode: false

    spacing: Tokens.space.s8
    visible: Notifs.count > 0

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.space.s8
        Text {
            text: "󰂚"
            color: Colors.onWallpaper(0.6)
            font.pixelSize: Tokens.font.label
            font.family: Properties.fontFamily
        }
        Text {
            text: Notifs.count === 1 ? "1 notification" : Notifs.count + " notifications"
            color: Colors.onWallpaper(0.7)
            font.pixelSize: Tokens.font.small
            font.bold: true
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: contentHeight
        interactive: false
        spacing: Tokens.space.s8
        model: Notifs.groupModel

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 }
                NumberAnimation { property: "x"; from: 40; to: 0; duration: 300; easing.type: Anim.standard }
            }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 250; easing.type: Anim.standard }
        }

        delegate: Rectangle {
            id: card
            required property int index
            required property string appName
            required property string appIcon
            required property double time
            required property bool closing
            required property var items

            // latest item of the group (re-evaluated when the group gets a new one → time changes)
            readonly property var latest: { time; return items.count > 0 ? items.get(0) : null }

            width: list.width
            height: visible ? col.implicitHeight + 20 : 0
            visible: index < root.maxGroups && !closing
            radius: Tokens.radius.card
            color: Properties.panelColor
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.s10 }
                spacing: Tokens.space.s2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s6
                    Image {
                        visible: card.appIcon !== ""
                        source: card.appIcon
                        sourceSize: Qt.size(16, 16)
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.appName + (card.items.count > 1 ? "  ·  " + card.items.count : "")
                        color: Colors.onWallpaper(0.6)
                        font.pixelSize: Tokens.font.caption
                        elide: Text.ElideRight
                    }
                    Text {
                        text: Notifs.relativeTime(card.time)
                        color: Colors.onWallpaper(0.4)
                        font.pixelSize: Tokens.font.micro
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !root.privateMode
                    text: card.latest?.summary ?? ""
                    color: "white"
                    font.pixelSize: Tokens.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== "" && !root.privateMode
                    text: (card.latest?.body ?? "").replace(/<[^>]*>/g, "")
                    color: Colors.onWallpaper(0.7)
                    font.pixelSize: Tokens.font.small
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
