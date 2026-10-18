import QtQuick
import QtQuick.Layouts
import qs.services

// ── A single notification inside a NotifGroup ──
// The newest item is always shown; the rest only while the group is
// expanded. Showing/hiding/removing all animate the same `reveal` value,
// which is what makes the dropdown and the per-item delete smooth.
Item {
    id: root

    required property var model
    required property int index
    property bool groupExpanded: false

    readonly property int uid: model.uid
    readonly property bool closing: model.closing
    readonly property bool shown: (index === 0 || groupExpanded) && !closing
    readonly property var actions: Notifs.actionsFor(uid)
    readonly property int gap: 6

    property real reveal: 0

    height: (inner.height + gap) * reveal
    clip: true

    Component.onCompleted: reveal = Qt.binding(() => root.shown ? 1 : 0)

    Behavior on reveal {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: inner
        y: root.gap
        width: root.width
        height: content.implicitHeight + 20
        radius: 9
        color: hover.hovered ? Colors.fade(0.1) : Colors.fade(0.05)
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        opacity: root.reveal
        x: root.closing ? root.width * 0.5 : 0

        Behavior on color { ColorAnimation { duration: Anim.color } }
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.InCubic } }

        HoverHandler { id: hover }

        // Click → run the default action (e.g. focus the app) and dismiss
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.activate(root.uid)
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    visible: root.model.image !== ""
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    Layout.alignment: Qt.AlignTop
                    radius: 8
                    clip: true
                    color: "transparent"

                    Image {
                        anchors.fill: parent
                        source: root.model.image
                        sourceSize: Qt.size(76, 76)
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: root.model.summary
                            textFormat: Text.PlainText
                            color: Colors.fade(0.88)
                            font { bold: true; pixelSize: 13 }
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: Notifs.relativeTime(root.model.time)
                            color: Colors.fade(0.33)
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        visible: root.model.body !== ""
                        text: root.model.body
                        textFormat: Text.StyledText
                        color: Colors.fade(0.66)
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }

                NotifActionButton {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: Qt.AlignTop
                    label: "✕"
                    fontSize: 11
                    onClicked: Notifs.dismiss(root.uid)
                }
            }

            RowLayout {
                visible: root.actions.length > 0
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.actions

                    NotifActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.text
                        onClicked: Notifs.invokeAction(root.uid, modelData.identifier)
                    }
                }
            }
        }
    }
}
