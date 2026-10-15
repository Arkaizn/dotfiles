import QtQuick
import QtQuick.Layouts
import qs.services

// ── One app's notifications in the center ──
// Header (icon, app name, count, time) + its notifications. Collapsed it
// shows only the newest one; the expand button drops down the rest.
// Delegate of NotificationsSection's Repeater over Notifs.groupModel.
Item {
    id: root

    required property var model
    required property int index

    readonly property int itemCount: model.items.count
    readonly property bool expanded: model.expanded
    readonly property bool closing: model.closing
    readonly property int gap: 8

    // 0 → collapsed slot, 1 → fully open
    property real reveal: 0

    height: (card.height + gap) * reveal
    clip: true

    Component.onCompleted: {
        reveal = Qt.binding(() => root.closing ? 0 : 1)
        card.x = Qt.binding(() => root.closing ? root.width * 0.6 : 0)
    }

    Behavior on reveal {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        width: root.width
        height: col.implicitHeight + 20
        radius: 12
        color: "#27000000"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, headerHover.hovered ? 0.16 : 0.08)

        // slide in from the right on add, out to the right on removal
        x: 60
        opacity: root.reveal

        Behavior on border.color { ColorAnimation { duration: Anim.color } }
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }

            // ── Header ────────────────────────────────────────
            Item {
                width: parent.width
                height: 40

                HoverHandler { id: headerHover }

                // Whole header toggles the dropdown (when there's something to drop down)
                MouseArea {
                    anchors.fill: parent
                    enabled: root.itemCount > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.toggleGroup(root.model.appName)
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 9
                        color: "#20ffffff"

                        Image {
                            id: appIconImg
                            anchors.fill: parent
                            anchors.margins: 5
                            source: root.model.appIcon
                            sourceSize: Qt.size(48, 48)
                            fillMode: Image.PreserveAspectFit
                        }
                        // Fallback: first letter of the app name
                        Text {
                            visible: appIconImg.status !== Image.Ready
                            anchors.centerIn: parent
                            text: (root.model.appName || "?").charAt(0).toUpperCase()
                            color: "#ccffffff"
                            font { bold: true; pixelSize: 15 }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.model.appName
                            color: "#e6ffffff"
                            font { bold: true; pixelSize: 13 }
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (root.itemCount > 1 ? root.itemCount + " notifications · " : "")
                                  + Notifs.relativeTime(root.model.time)
                            color: "#70ffffff"
                            font.pixelSize: 11
                        }
                    }

                    // Expand / collapse the dropdown
                    NotifActionButton {
                        visible: root.itemCount > 1
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: 52
                        active: root.expanded
                        label: (root.expanded ? "" : "") + "  " + root.itemCount
                        fontSize: 11
                        onClicked: Notifs.toggleGroup(root.model.appName)
                    }

                    // Clear this app's notifications
                    NotifActionButton {
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: 32
                        label: "✕"
                        onClicked: Notifs.dismissGroup(root.model.appName)
                    }
                }
            }

            // ── Notifications (newest first) ──────────────────
            Repeater {
                model: root.model.items

                NotifItem {
                    width: col.width
                    groupExpanded: root.expanded
                }
            }
        }
    }
}
