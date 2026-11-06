import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// One part of the path bar: a folder name you can click. `current` is the open
// folder; `ahead` a folder below it you came from (kept, dimmed, like Nautilus).
Pressable {
    id: c
    property string label: ""
    property string icon: ""
    property bool current: false
    property bool ahead: false

    implicitWidth: row.implicitWidth + 2 * Tokens.space.s8
    implicitHeight: Tokens.size.controlSmall
    focusRadius: Tokens.radius.md
    accessibleName: label

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        color: c.pressed ? Colors.fillPressed : c.hovered ? Colors.fillHover : "transparent"
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.space.gap
        Text {
            visible: c.icon !== ""
            text: c.icon
            color: c.current ? Colors.accent : Colors.fade(0.55)
            font.pixelSize: Tokens.font.body
            font.family: Properties.fontFamily
        }
        Text {
            text: c.label
            // a 300-character name doesn't push the rest away
            Layout.maximumWidth: Tokens.size.row * 5
            elide: Text.ElideMiddle
            color: c.current ? Colors.ink : Colors.fade(c.ahead ? 0.38 : 0.65)
            font.pixelSize: Tokens.font.body
            font.bold: c.current
            font.family: Properties.fontFamily
        }
    }
}
