import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services

// ── Notifications part of the notification center ──
// All state lives in the Notifs singleton; this is only the view.
ColumnLayout {
    id: root

    property int maxListHeight: PanelGeometry.notifications.height   // Settings → Panel editor
    property bool fullHeight: false      // always maxListHeight high (resizing it live)
    readonly property bool empty: Notifs.count === 0

    spacing: 8

    // ── Header ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 8

        Text {
            text: "Notifications"
            color: Colors.ink
            font { bold: true; pixelSize: 14 }
        }

        Rectangle {
            opacity: root.empty ? 0 : 1
            Layout.preferredWidth: countLabel.implicitWidth + 12
            Layout.preferredHeight: 18
            radius: 9
            color: Colors.fade(0.25)
            Behavior on opacity { NumberAnimation { duration: Anim.hover } }

            Text {
                id: countLabel
                anchors.centerIn: parent
                text: Notifs.count
                color: Colors.fade(0.87)
                font { bold: true; pixelSize: 10 }
            }
        }

        Item { Layout.fillWidth: true }

        // do not disturb (Settings → Notifications has the schedule)
        NotifActionButton {
            label: (Notifs.dnd ? "󰂛  " : "󰂚  ") + (Notifs.dndScheduled && !Notifs.dndManual ? "Quiet (schedule)"
                   : Notifs.dnd ? "Quiet" + (Notifs.missed > 0 ? " · " + Notifs.missed + " held back" : "") : "Do not disturb")
            Layout.preferredHeight: 30
            active: Notifs.dnd
            onClicked: Notifs.setDnd(!Notifs.dndManual)
        }

        // collapses when empty, so "Do not disturb" moves to the right edge
        NotifActionButton {
            label: "Clear all"
            Layout.preferredHeight: 30
            Layout.preferredWidth: root.empty ? 0 : implicitWidth
            visible: Layout.preferredWidth > 0
            clip: true
            enabled: !root.empty
            opacity: root.empty ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Anim.hover } }
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            onClicked: Notifs.clearAll()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Colors.fade(0.2)
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
            color: Colors.fade(0.4)
            font { pixelSize: 12; family: Properties.fontFamily }
        }
    }

    // ── Groups ────────────────────────────────────────────────
    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.preferredHeight: root.fullHeight ? root.maxListHeight : Math.min(groupsCol.height, root.maxListHeight)
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
