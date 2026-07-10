import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

// Root is now a plain Item, not a window itself.
// It just holds state + spawns one PanelWindow per notification via Variants.
Item {
    id: root

    // Plain JS array of notification objects: {uid, summary, body, appName, appIcon, actions}
    property var notifications: []

    // uid -> height, kept as its own property (reassigned wholesale) so bindings
    // that read it recompute reactively.
    property var notifHeights: ({})

    readonly property int gap: 6
    readonly property int edgeMargin: 10

    function notify(summary, body, appName, appIcon, actions) {
        let uid = Date.now()
        let list = notifications.slice()
        list.push({
            "uid":     uid,
            "summary": summary ?? "",
            "body":    body ?? "",
            "appName": appName ?? "",
            "appIcon": appIcon ?? "",
            "actions": actions ?? []
        })
        notifications = list
        removeTimer.createObject(root, { "targetUid": uid })
    }

    function removeByUid(uid) {
        notifications = notifications.filter(n => n.uid !== uid)
        let h = Object.assign({}, notifHeights)
        delete h[uid]
        notifHeights = h
    }

    function setHeight(uid, h) {
        let hh = Object.assign({}, notifHeights)
        hh[uid] = h
        notifHeights = hh
    }

    // Sum of heights (+gap) of every notification above this one, in order.
    function offsetFor(uid) {
        let total = 0
        for (let i = 0; i < notifications.length; i++) {
            let n = notifications[i]
            if (n.uid === uid) break
            total += (notifHeights[n.uid] ?? 0) + gap
        }
        return total
    }

    function slideOutByUid(uid) {
        for (let i = 0; i < notifVariants.instances.length; i++) {
            let win = notifVariants.instances[i]
            if (win && win.modelData && win.modelData.uid === uid) {
                win.slideOut(() => root.removeByUid(uid))
                return
            }
        }
        // fallback if the window wasn't found for some reason
        removeByUid(uid)
    }

    Component {
        id: removeTimer
        Timer {
            property var targetUid: 0
            interval: 5000
            running: true
            onTriggered: {
                root.slideOutByUid(targetUid)
                destroy()
            }
        }
    }

    Variants {
        id: notifVariants
        model: root.notifications

        PanelWindow {
            id: win
            required property var modelData

            visible: true
            anchors { top: true; right: true }
            implicitWidth: 360
            implicitHeight: Math.max(card.implicitHeight + 20, 1)
            color: "transparent"

            Behavior on implicitHeight {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            margins {
                top: root.edgeMargin + root.offsetFor(modelData.uid)
                right: root.edgeMargin
            }

            // Smoothly shift when notifications above this one are added/removed.
            Behavior on margins.top {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Each window has its own unambiguous "card" -> blur tracks it correctly.
            BackgroundEffect.blurRegion: Region { item: card; radius: 10 }

            function slideOut(callback) {
                slideOutAnim.callback = callback
                slideOutAnim.start()
            }

            Item {
                id: content
                anchors.fill: parent
                clip: true

                readonly property real dismissThreshold: 110

                Component.onCompleted: {
                    content.x = 400
                    content.opacity = 0
                    slideIn.start()
                }

                ParallelAnimation {
                    id: slideIn
                    NumberAnimation { target: content; property: "x"; to: 0; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                }

                ParallelAnimation {
                    id: slideOutAnim
                    property var callback: null
                    NumberAnimation { target: content; property: "x"; to: 400; duration: 250; easing.type: Easing.InCubic }
                    NumberAnimation { target: content; property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                    onFinished: if (callback) callback()
                }

                ParallelAnimation {
                    id: snapBack
                    NumberAnimation { target: content; property: "x"; to: 0; duration: 240; easing.type: Easing.OutBack }
                    NumberAnimation { target: content; property: "y"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                }

                // Fades the card a bit as it's dragged, purely visual feedback.
                Connections {
                    target: content
                    function onXChanged() {
                        if (dragArea.drag.active) {
                            content.opacity = Math.max(0.35, 1 - Math.abs(content.x) / 300)
                        }
                    }
                    function onYChanged() {
                        if (dragArea.drag.active) {
                            content.opacity = Math.max(0.35, 1 - Math.abs(content.y) / 300)
                        }
                    }
                }

                Rectangle {
                    id: card
                    property var notifActions: win.modelData.actions ?? []

                    anchors { left: parent.left; right: parent.right }
                    implicitHeight: innerCol.implicitHeight + 24
                    radius: 10
                    color: "#27000000"

                    Behavior on implicitHeight {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    onImplicitHeightChanged: root.setHeight(win.modelData.uid, implicitHeight + 20)
                    Component.onCompleted: root.setHeight(win.modelData.uid, implicitHeight + 20)

                    // Close button, using the shared button theme
                    Item {
                        id: closeButton
                        z: 10
                        anchors { top: parent.top; right: parent.right; margins: 6 }
                        implicitWidth: closeButtonBg.implicitWidth + Properties.buttonWidth
                        implicitHeight: Properties.buttonHeight
                        property bool hovered: closeMouseArea.containsMouse

                        ButtonBackground {
                            id: closeButtonBg
                            hovered: closeButton.hovered
                            iconText: "✕"
                            iconSize: 11
                        }

                        MouseArea {
                            id: closeMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: closeButtonBg.scale = Properties.onEnteredButtonScale
                            onExited: closeButtonBg.scale = Properties.onExitedButtonScale
                            onClicked: win.slideOut(() => root.removeByUid(win.modelData.uid))
                        }
                    }

                    ColumnLayout {
                        id: innerCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                        }
                        spacing: 6

                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true

                            Image {
                                visible: win.modelData.appIcon !== "" && win.modelData.appIcon !== null
                                sourceSize.width: 60
                                sourceSize.height: 60
                                source: win.modelData.appIcon ? Quickshell.iconPath(win.modelData.appIcon, true) : ""
                            }

                            ColumnLayout {
                                spacing: 3
                                Layout.fillWidth: true

                                Text {
                                    text: win.modelData.appName
                                    font { bold: true; pixelSize: 11 }
                                    color: "#88ffffff"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: win.modelData.summary
                                    font { bold: true; pixelSize: 15 }
                                    color: "#cdffffff"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Divider between title (app name + summary) and body text
                        Rectangle {
                            visible: win.modelData.body !== ""
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            height: 1
                            color: "#22ffffff"
                        }

                        Text {
                            visible: win.modelData.body !== ""
                            text: win.modelData.body
                            color: "#acffffff"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Action buttons
                        RowLayout {
                            visible: card.notifActions.filter(a => a.identifier !== "default").length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: card.notifActions.filter(a => a.identifier !== "default")
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 6
                                    color: "#40ffffff"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.text ?? ""
                                        color: "#ddffffff"
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.invoke()
                                            win.slideOut(() => root.removeByUid(win.modelData.uid))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Drag to move (up/down/right) + click card = default action.
                    // z:-1 keeps this below the close button and action buttons
                    // so they still get their own clicks first.
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        z: -1
                        drag.target: content
                        drag.axis: Drag.XAndYAxis

                        onPressed: {
                            slideIn.stop()
                            snapBack.stop()
                        }

                        onReleased: {
                            if (content.x > content.dismissThreshold) {
                                win.slideOut(() => root.removeByUid(win.modelData.uid))
                            } else {
                                snapBack.restart()
                            }
                        }

                        onClicked: {
                            let def = card.notifActions.find(a => a.identifier === "default")
                            if (def) def.invoke()
                            win.slideOut(() => root.removeByUid(win.modelData.uid))
                        }
                    }
                }
            }
        }
    }
}
