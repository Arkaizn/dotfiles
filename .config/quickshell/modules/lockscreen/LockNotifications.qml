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

    spacing: 8
    visible: Notifs.count > 0

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: "󰂚"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 14
            font.family: Properties.fontFamily
        }
        Text {
            text: Notifs.count === 1 ? "1 notification" : Notifs.count + " notifications"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 12
            font.bold: true
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: contentHeight
        interactive: false
        spacing: 8
        model: Notifs.groupModel

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 }
                NumberAnimation { property: "x"; from: 40; to: 0; duration: 300; easing.type: Easing.OutCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 250; easing.type: Easing.OutCubic }
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
            radius: 14
            color: Properties.panelColor
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
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
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        text: Notifs.relativeTime(card.time)
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: 10
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: card.latest?.summary ?? ""
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: (card.latest?.body ?? "").replace(/<[^>]*>/g, "")
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
