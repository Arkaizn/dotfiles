import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services

// ── Notifications part of the notification center ──
// All state lives in the Notifs singleton; this is only the view.
ColumnLayout {
    id: root

    readonly property int maxListHeight: 420
    readonly property bool empty: Notifs.count === 0

    spacing: 8

    // ── Header ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 8

        Text {
            text: "Notifications"
            color: "white"
            font { bold: true; pixelSize: 14 }
        }

        Rectangle {
            opacity: root.empty ? 0 : 1
            Layout.preferredWidth: countLabel.implicitWidth + 12
            Layout.preferredHeight: 18
            radius: 9
            color: "#40ffffff"
            Behavior on opacity { NumberAnimation { duration: Anim.hover } }

            Text {
                id: countLabel
                anchors.centerIn: parent
                text: Notifs.count
                color: "#ddffffff"
                font { bold: true; pixelSize: 10 }
            }
        }

        Item { Layout.fillWidth: true }

        NotifActionButton {
            label: "Clear all"
            Layout.preferredHeight: 30
            enabled: !root.empty
            opacity: root.empty ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Anim.hover } }
            onClicked: Notifs.clearAll()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: "#33ffffff"
    }

    // ── Empty state (fades/collapses instead of popping) ──────
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.empty ? 56 : 0
        opacity: root.empty ? 1 : 0
        clip: true
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Text {
            anchors.centerIn: parent
            text: "   No notifications"
            color: "#66ffffff"
            font { pixelSize: 12; family: Properties.fontFamily }
        }
    }

    // ── Groups ────────────────────────────────────────────────
    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(groupsCol.height, root.maxListHeight)
        contentHeight: groupsCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: groupsCol
            width: flick.width

            Repeater {
                model: Notifs.groupModel

                NotifGroup {
                    width: groupsCol.width
                }
            }
        }
    }
}
