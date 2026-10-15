import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.services

// ── A single notification popup ──
// Delegate of NotifPopup's Repeater over Notifs.popupModel.
//
// Enter: slides in from the right while its slot grows open.
// Exit:  slides out to the right (from wherever it is, so a drag just
//        continues), then the slot collapses so the cards below move up.
// Drag right past the threshold or click anywhere → dismiss.
Item {
    id: root

    // model roles
    required property int index
    required property int uid
    required property string appName
    required property string appIcon
    required property string image
    required property string summary
    required property string body
    required property int urgency
    required property int timeout
    required property bool closing

    // set by NotifPopup
    property var window
    property real xOffset: 0
    property real yOffset: 0

    readonly property int gap: 8
    readonly property real dismissThreshold: 90
    readonly property bool critical: urgency === NotificationUrgency.Critical
    readonly property var actions: Notifs.actionsFor(uid)

    // 0 → slot collapsed, 1 → slot fully open
    property real reveal: 0
    // 1 → 0 over the timeout; paused while hovered
    property real progress: 1

    height: (card.height + gap) * reveal
    clip: true

    Component.onCompleted: {
        card.x = width + 20
        enterAnim.start()
        if (!critical) timeoutAnim.start()
        window?.addRegion(blur)
    }
    Component.onDestruction: window?.removeRegion(blur)

    onClosingChanged: if (closing) {
        enterAnim.stop()
        snapBack.stop()
        timeoutAnim.stop()
        exitAnim.start()
    }

    // ── Animations ────────────────────────────────────────────
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "x"; to: 0; duration: 340; easing.type: Easing.OutCubic }
    }

    // Total must stay under Notifs.exitDuration, after which the model entry is removed.
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: card; property: "x"; to: root.width + 20; duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "reveal"; to: 0; duration: 180; easing.type: Easing.OutCubic }
    }

    NumberAnimation {
        id: snapBack
        target: card; property: "x"; to: 0
        duration: 260; easing.type: Easing.OutBack
    }

    NumberAnimation {
        id: timeoutAnim
        target: root; property: "progress"
        from: 1; to: 0
        duration: root.timeout
        paused: running && (cardHover.hovered || dragArea.pressed)
        onFinished: Notifs.hidePopup(root.uid)
    }

    // Blur behind this card, in window coordinates so it follows the slide/drag.
    Region {
        id: blur
        x: root.xOffset + root.x + card.x
        y: root.yOffset + root.y + card.y
        width: card.width
        height: Math.min(card.height, root.height)
        radius: card.radius
    }

    // ── Card ──────────────────────────────────────────────────
    Rectangle {
        id: card
        width: root.width
        height: content.implicitHeight + 24
        radius: 12
        color: "#30000000"
        border.width: 1
        border.color: root.critical ? "#a0ff5f5f" : Qt.rgba(1, 1, 1, cardHover.hovered ? 0.2 : 0.1)
        // fade as it's dragged away
        opacity: 1 - Math.max(0, x) / (root.width * 1.4)

        Behavior on border.color { ColorAnimation { duration: Anim.color } }

        HoverHandler { id: cardHover }

        // Drag right to dismiss, click to activate. Sits below the buttons (z: -1).
        MouseArea {
            id: dragArea
            z: -1
            anchors.fill: parent
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: card
            drag.axis: Drag.XAxis
            drag.minimumX: 0
            drag.maximumX: root.width
            drag.threshold: 6

            property bool dragged: false
            onPressed: {
                dragged = false
                snapBack.stop()
                // grabbed mid slide-in: finish the entrance so it doesn't fight the drag
                if (enterAnim.running) enterAnim.complete()
            }
            onPositionChanged: if (drag.active) dragged = true
            onReleased: {
                if (!dragged) return
                if (card.x > root.dismissThreshold) Notifs.dismiss(root.uid)
                else snapBack.start()
            }
            onClicked: if (!dragged) Notifs.activate(root.uid)
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Notification image (avatar, album art, …) or the app icon
                Rectangle {
                    readonly property string src: root.image || root.appIcon
                    visible: src !== ""
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    Layout.alignment: Qt.AlignTop
                    radius: 10
                    color: "#20ffffff"
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: root.image ? 0 : 6
                        source: parent.src
                        sourceSize: Qt.size(84, 84)
                        fillMode: root.image ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Text {
                        text: root.appName
                        color: "#88ffffff"
                        font { bold: true; pixelSize: 11 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        // leave room for the close button
                        Layout.rightMargin: 26
                    }

                    Text {
                        text: root.summary
                        textFormat: Text.PlainText
                        color: "#e6ffffff"
                        font { bold: true; pixelSize: 14 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.body !== ""
                        text: root.body
                        textFormat: Text.StyledText
                        color: "#b0ffffff"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            // Action buttons (the "default" action is the card click itself)
            RowLayout {
                visible: root.actions.length > 0
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.actions

                    NotifActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        label: modelData.text
                        onClicked: Notifs.invokeAction(root.uid, modelData.identifier)
                    }
                }
            }
        }

        NotifActionButton {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            width: 26; height: 26
            label: "✕"
            fontSize: 11
            onClicked: Notifs.dismiss(root.uid)
        }

        // Remaining-time bar
        Rectangle {
            visible: !root.critical
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: card.radius; bottomMargin: 1 }
            width: (parent.width - card.radius * 2) * root.progress
            height: 2
            radius: 1
            color: "#40ffffff"
        }
    }
}
