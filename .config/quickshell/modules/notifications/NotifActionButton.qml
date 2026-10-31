import QtQuick
import qs.components
import qs.services

// Notification buttons (close, actions, expand, clear): a compact label button
// in the shared button look. Keyboard, focus ring and tooltip from Pressable.
//   NotifActionButton { label: "Reply"; onClicked: … }
Pressable {
    id: root

    property string label: ""
    property int fontSize: Tokens.font.small
    property bool active: false      // persistent "on" look, e.g. an expanded group

    implicitWidth: text.implicitWidth + 20
    implicitHeight: 30
    accessibleName: tooltip !== "" ? tooltip : label
    focusRadius: Tokens.radius.md
    scale: pressed ? 0.94 : hovered ? 1.04 : 1
    Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        border.width: Tokens.border.thin
        border.color: Colors.fade(root.hovered || root.active ? 0.28 : 0.14)
        gradient: ButtonGradient { hovered: root.hovered || root.active }
        Behavior on border.color { ColorAnimation { duration: Anim.fast } }
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.hovered || root.active ? Colors.ink : Colors.fade(0.87)
        font.pixelSize: root.fontSize
        font.family: Properties.fontFamily
    }
}
