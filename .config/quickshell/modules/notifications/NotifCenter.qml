import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.components

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
        right: true
    }
    implicitWidth: 420
    implicitHeight: Math.min(mainCol.implicitHeight + 40, 600)
    color: "transparent"
    exclusiveZone: 0

    property alias groupCount: groupModel.count
    property bool hasBeenHovered: false

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
        enterDuration: 150
        exitDuration: 150
        onExitFinished: root.visible = false
    }

    function toggle() {
        if (root.visible) {
            anim.exit()
        } else {
            root.visible = true
            BarState.popupOpenRight = true
            enterTimer.start()
        }
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: anim.enter()
    }

    Timer {
        id: autoCloseTimer
        interval: 500
        repeat: false
        onTriggered: {
            anim.exit()
            BarState.popupOpenRight = false
            hasBeenHovered = false
        }
    }

    // Called from NotifPopup to mirror notifications here
    function addNotification(uid, summary, body, appName, appIcon, actionsJson) {
        for (let i = 0; i < groupModel.count; i++) {
            if (groupModel.get(i).appName === appName) {
                let group = groupModel.get(i)
                let items = JSON.parse(group.itemsJson)
                items.unshift({ uid, summary, body, actionsJson })
                groupModel.setProperty(i, "itemsJson", JSON.stringify(items))
                groupModel.setProperty(i, "latestSummary", summary)
                return
            }
        }
        groupModel.append({
            "appName":       appName,
            "appIcon":       appIcon,
            "latestSummary": summary,
            "itemsJson":     JSON.stringify([{ uid, summary, body, actionsJson }]),
            "expanded":      false
        })
    }

    function removeGroup(appName) {
        for (let i = 0; i < groupModel.count; i++) {
            if (groupModel.get(i).appName === appName) {
                groupModel.remove(i)
                return
            }
        }
    }

    function clearAll() {
        groupModel.clear()
    }

    ListModel { id: groupModel }

    // Inverse corner — left side only, panel is flush right
    InverseCorner {
        anchors.right: rect.left
        anchors.top: rect.top
        corner: "topRight"
        color: rect.color
        radius: 12
    }

    // ── Main panel ─────────────────────────────────────────────
    Rectangle {
        id: rect
        implicitHeight: parent.height - 20
        clip: true
        opacity: 0
        y: -height
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: 10
            rightMargin: 10
        }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        // Content pinned to bottom — reveals as rect slides down
        ColumnLayout {
            id: mainCol
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: 10
            }
            height: Math.min(mainCol.implicitHeight, rect.implicitHeight - 20)
            spacing: 8

            // ── Header ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Notifications"
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    Layout.fillWidth: true
                }

                // Clear all button
                Rectangle {
                    implicitWidth: clearAllLabel.implicitWidth + 20
                    implicitHeight: 28
                    radius: 8
                    visible: groupModel.count > 0

                    property bool hovered: clearAllMouse.containsMouse
                    gradient: ButtonGradient { hovered: hovered }

                    Text {
                        id: clearAllLabel
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: "#ddffffff"
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: clearAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearAll()
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }
                    onHoveredChanged: scale = hovered ? 1.05 : 1.0
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#33ffffff"
            }

            // ── Empty state ───────────────────────────────────────
            Text {
                visible: groupModel.count === 0
                text: "No notifications"
                color: "#666666"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 16
            }

            // ── Notification groups ───────────────────────────────
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: groupModel.count > 0
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    id: groupsCol
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: groupModel

                        delegate: Rectangle {
                            id: groupCard
                            required property var model
                            required property int index

                            property var items: JSON.parse(model.itemsJson ?? "[]")
                            property bool expanded: model.expanded

                            Layout.fillWidth: true
                            implicitHeight: groupInner.implicitHeight + 20
                            radius: 10
                            color: "#27000000"

                            // Slide in animation
                            x: 0
                            opacity: 1
                            Component.onCompleted: {
                                groupCard.x = 420
                                groupCard.opacity = 0
                                slideIn.start()
                            }
                            ParallelAnimation {
                                id: slideIn
                                NumberAnimation { target: groupCard; property: "x"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                NumberAnimation { target: groupCard; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                id: groupInner
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 12
                                }
                                spacing: 6

                                // ── Group header row ──────────────
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Image {
                                        visible: groupCard.model.appIcon !== "" && groupCard.model.appIcon !== null
                                        width: 24; height: 24
                                        source: groupCard.model.appIcon ? Quickshell.iconPath(groupCard.model.appIcon, true) : ""
                                    }

                                    Text {
                                        text: groupCard.model.appName
                                        font { bold: true; pixelSize: 12 }
                                        color: "#88ffffff"
                                    }

                                    // Badge count
                                    Rectangle {
                                        visible: groupCard.items.length > 1
                                        width: countLabel.implicitWidth + 10
                                        height: 18
                                        radius: 9
                                        color: "#40ffffff"
                                        Text {
                                            id: countLabel
                                            anchors.centerIn: parent
                                            text: groupCard.items.length
                                            color: "#ddffffff"
                                            font { bold: true; pixelSize: 10 }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Expand/collapse toggle (only if >1 notif)
                                    Text {
                                        visible: groupCard.items.length > 1
                                        text: groupCard.expanded ? "▲" : "▼"
                                        color: "#60ffffff"
                                        font.pixelSize: 10
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: groupModel.setProperty(groupCard.index, "expanded", !groupCard.expanded)
                                        }
                                    }

                                    // Dismiss group button
                                    Text {
                                        text: "✕"
                                        color: "#60ffffff"
                                        font.pixelSize: 12
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeGroup(groupCard.model.appName)
                                        }
                                    }
                                }

                                // ── Collapsed: show only latest ───
                                ColumnLayout {
                                    visible: !groupCard.expanded
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: groupCard.items[0]?.summary ?? ""
                                        font { bold: true; pixelSize: 14 }
                                        color: "#cdffffff"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: (groupCard.items[0]?.body ?? "") !== ""
                                        text: groupCard.items[0]?.body ?? ""
                                        color: "#acffffff"
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // ── Expanded: show all stacked ────
                                ColumnLayout {
                                    visible: groupCard.expanded
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: groupCard.items

                                        delegate: ColumnLayout {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            spacing: 3

                                            // Divider between items
                                            Rectangle {
                                                visible: index > 0
                                                Layout.fillWidth: true
                                                height: 1
                                                color: "#20ffffff"
                                            }

                                            Text {
                                                text: modelData.summary ?? ""
                                                font { bold: true; pixelSize: 13 }
                                                color: "#cdffffff"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: (modelData.body ?? "") !== ""
                                                text: modelData.body ?? ""
                                                color: "#acffffff"
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        HoverHandler {
            id: rectHover
            onHoveredChanged: {
                if (hovered) {
                    hasBeenHovered = true
                    autoCloseTimer.stop()
                } else if (hasBeenHovered) {
                    autoCloseTimer.start()
                }
            }
        }
    }
}
