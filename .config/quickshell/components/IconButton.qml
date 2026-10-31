import QtQuick
import QtQuick.Layouts
import qs.services

// Square icon button with the same look/feel as the bar buttons
// (ButtonBackground + hover/press scale). Tab / Space / Enter, focus ring,
// tooltip and screen-reader name come from Pressable.
//
//   IconButton {
//       icon: "󰑐"
//       tooltip: "Rescan"     // also its accessible name — set it on every icon-only button
//       active: false         // keeps the hovered look, e.g. the selected mode
//       interactive: true     // false = disabled (dimmed, no clicks / hover)
//       busy: false           // true = the icon turns (Spinner), clicks are ignored
//       onClicked: doThing()
//   }
// A trash / archive / star / junk icon gets its color (Icons.tint, Shell → Icons)
// unless textColor is set.
Pressable {
    id: root

    property string icon: ""
    property bool active: false
    property int iconSize: Tokens.icon.md
    property color textColor: Icons.tint(icon, Properties.color)

    implicitWidth: Tokens.size.control
    implicitHeight: Tokens.size.control
    // in a layout: never squeezed below its size (the texts next to it give way)
    Layout.minimumWidth: implicitWidth
    focusRadius: Tokens.radius.md

    ButtonBackground {
        hovered: root.active || root.hovered || root.activeFocus
        iconText: root.busy ? "" : root.icon
        iconSize: root.iconSize
        textColor: root.textColor
        scale: !root.interactive ? Properties.onExitedButtonScale
             : root.pressed ? Properties.onPressedButtonScale
             : root.hovered ? Properties.onEnteredButtonScale
             : Properties.onExitedButtonScale
        Spinner {
            anchors.centerIn: parent
            visible: root.busy
            running: root.busy
            glyph: root.icon || "󰑓"
            size: root.iconSize
            color: root.textColor
        }
    }
}
