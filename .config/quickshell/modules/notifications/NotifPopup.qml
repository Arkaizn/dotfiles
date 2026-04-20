import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

PanelWindow {
    id: root
    visible: true
    anchors {
        top: true
        right: true
    }
    implicitWidth: 360
    implicitHeight: Math.max(contentCol.implicitHeight + 20, 1)
    color: "transparent"

    function notify(summary, body, appName, appIcon, actions) {
        let uid = Date.now()
        notifList.append({
            "uid":         uid,
            "summary":     summary  ?? "",
            "body":        body     ?? "",
            "appName":     appName  ?? "",
            "appIcon":     appIcon  ?? "",
            "actionsJson": JSON.stringify(actions ?? [])
        })
        removeTimer.createObject(root, { "targetUid": uid })
    }

    function removeByUid(uid) {
        for (let i = 0; i < notifList.count; i++) {
            if (notifList.get(i).uid === uid) {
                notifList.remove(i)
                break
            }
        }
    }

    function slideOutByUid(uid) {
        for (let i = 0; i < repeater.count; i++) {
            let wrapper = repeater.itemAt(i)
            if (wrapper && wrapper.model.uid === uid) {
                wrapper.slideOut(() => root.removeByUid(uid))
                return
            }
        }
        // fallback if item not found
        removeByUid(uid)
    }

    ListModel { id: notifList }

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

    Flickable {
        id: flick
        anchors {
            fill: parent
            margins: 10
        }
        contentHeight: contentCol.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        opacity: notifList.count > 0 ? 1 : 0

        ColumnLayout {
            id: contentCol
            width: flick.width
            spacing: 6

            Repeater {
                id: repeater
                model: notifList

                delegate: Item {
                    id: cardWrapper
                    required property var model

                    Layout.fillWidth: true
                    implicitHeight: card.implicitHeight

                    Component.onCompleted: {
                        cardWrapper.x = 400
                        cardWrapper.opacity = 0
                        slideIn.start()
                    }

                    function slideOut(callback) {
                        slideOutAnim.callback = callback
                        slideOutAnim.start()
                    }

                    ParallelAnimation {
                        id: slideIn
                        NumberAnimation { target: cardWrapper; property: "x"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { target: cardWrapper; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                    }

                    ParallelAnimation {
                        id: slideOutAnim
                        property var callback: null
                        NumberAnimation { target: cardWrapper; property: "x"; to: 400; duration: 250; easing.type: Easing.InCubic }
                        NumberAnimation { target: cardWrapper; property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                        onFinished: if (callback) callback()
                    }

                    Rectangle {
                        id: card
                        property var notifActions: JSON.parse(cardWrapper.model.actionsJson ?? "[]")

                        anchors { left: parent.left; right: parent.right }
                        implicitHeight: innerCol.implicitHeight + 24
                        radius: 10
                        color: "#27000000"

                        // Close button
                        Text {
                            z: 10
                            anchors { top: parent.top; right: parent.right; margins: 6 }
                            text: "✕"
                            color: "#80ffffff"
                            font.pixelSize: 12
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cardWrapper.slideOut(() => root.removeByUid(cardWrapper.model.uid))
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
                                    visible: cardWrapper.model.appIcon !== "" && cardWrapper.model.appIcon !== null
                                    width: 32; height: 32
                                    source: cardWrapper.model.appIcon ? Quickshell.iconPath(cardWrapper.model.appIcon, true) : ""
                                }

                                ColumnLayout {
                                    spacing: 3
                                    Layout.fillWidth: true

                                    Text {
                                        text: cardWrapper.model.appName
                                        font { bold: true; pixelSize: 11 }
                                        color: "#88ffffff"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: cardWrapper.model.summary
                                        font { bold: true; pixelSize: 15 }
                                        color: "#cdffffff"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: cardWrapper.model.body !== ""
                                        text: cardWrapper.model.body
                                        color: "#acffffff"
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
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
                                                cardWrapper.slideOut(() => root.removeByUid(cardWrapper.model.uid))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Click card = default action
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: {
                                let def = card.notifActions.find(a => a.identifier === "default")
                                if (def) def.invoke()
                                cardWrapper.slideOut(() => root.removeByUid(cardWrapper.model.uid))
                            }
                        }
                    }
                }
            }
        }
    }
}