import QtQuick
import qs.components
import qs.services

// Clickable button in the shared button look (ButtonGradient + soft border),
// used for all notification buttons: close, actions, expand, clear.
Rectangle {
    id: root

    property string label: ""
    property int fontSize: 12
    property bool active: false      // persistent "on" look, e.g. an expanded group
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    implicitWidth: text.implicitWidth + 20
    implicitHeight: 30
    radius: 8
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, hovered || active ? 0.28 : 0.14)
    gradient: ButtonGradient { hovered: root.hovered || root.active }
    scale: mouse.pressed ? 0.94 : hovered ? 1.04 : 1

    Behavior on scale { NumberAnimation { duration: Anim.hover; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Anim.color } }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.hovered || root.active ? "white" : "#ddffffff"
        font.pixelSize: root.fontSize
        font.family: Properties.fontFamily
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
