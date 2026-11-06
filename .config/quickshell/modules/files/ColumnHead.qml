import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons

// A column head of the list view: its name, an arrow when the list is sorted by
// it. Right-click: the columns menu (rightClicked). `sortable: false` (permissions)
// only shows its name.
Pressable {
    id: h
    property string label: ""
    property bool active: false
    property bool reverse: false
    property bool alignRight: false
    property bool sortable: true

    implicitHeight: Tokens.size.controlSmall
    focusRadius: Tokens.radius.md
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    tooltip: !sortable ? label + " — right-click for the columns"
           : active ? (reverse ? "Sorted descending — click for ascending" : "Sorted ascending — click for descending") : "Sort by " + label.toLowerCase()
    accessibleName: sortable ? "Sort by " + label : label

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        color: h.hovered && h.sortable ? Colors.fillHover : "transparent"
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s8
        anchors.rightMargin: Tokens.space.s8
        spacing: Tokens.space.s4
        layoutDirection: h.alignRight ? Qt.RightToLeft : Qt.LeftToRight
        Text {
            text: h.label
            color: h.active ? Colors.ink : Colors.fade(0.45)
            font.pixelSize: Tokens.font.caption
            font.bold: h.active
            font.family: Properties.fontFamily
        }
        Text {
            visible: h.active
            text: h.reverse ? FmIcons.g.down : FmIcons.g.up
            color: Colors.accent
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
        }
        Item { Layout.fillWidth: true }
    }
}
