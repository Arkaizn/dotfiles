import QtQuick
import QtQuick.Layouts
import qs.services

// Button with icon + text in the ButtonBackground style. Tab / Space /
// Enter, focus ring, tooltip and screen-reader name come from Pressable.
//
//   ActionButton {
//       icon: "󰆴"; text: "Delete"
//       variant: "danger"     // "default" | "primary" (the main action) | "danger" | "ghost" (no frame)
//       interactive: ok       // false = disabled (dimmed)
//       busy: saving          // spinner instead of the icon, clicks ignored
//       tooltip: "…"          // optional
//       onClicked: …
//   }
// `primary: true` is the older way to say variant "primary" (still works).
// A trash / archive / star / junk icon gets its color (Icons.tint).
Pressable {
    id: root

    property string icon: ""
    property string text: ""
    property string variant: primary ? "primary" : "default"
    property bool primary: false
    property color textColor: variant === "danger" ? Colors.danger : Colors.ink

    readonly property bool _primary: variant === "primary"
    readonly property bool _ghost: variant === "ghost"

    implicitWidth: row.implicitWidth + 26
    implicitHeight: Tokens.size.control
    // in a layout: never squeezed below its size (the texts next to it give way)
    Layout.minimumWidth: implicitWidth
    accessibleName: text !== "" ? text : tooltip
    focusRadius: Tokens.radius.md

    // the whole button scales (background and text together); wide buttons
    // grow at most 4px per side, so they stay inside the edges around them
    scale: !interactive || busy ? 1
         : pressed ? Properties.onPressedButtonScale
         : hovered ? 1 + Math.min((Properties.onEnteredButtonScale - 1) * 0.4, 8 / Math.max(1, width)) : 1
    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

    ButtonBackground {
        visible: !root._ghost || root.hovered || root.activeFocus
        hovered: root.interactive && (root._primary || root.hovered || root.activeFocus)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: root.icon !== "" && !root.busy
            text: root.icon
            color: root._primary ? Colors.accent : Icons.tint(root.icon, root.textColor)
            font.pixelSize: Tokens.font.label
            font.family: Properties.fontFamily
        }
        Spinner {
            visible: root.busy
            running: root.busy
            glyph: root.icon || "󰑓"
            size: Tokens.font.label
            color: root._primary ? Colors.accent : root.textColor
        }
        Text {
            text: root.text
            color: root.textColor
            font.pixelSize: Tokens.font.small
            font.bold: root._primary
            font.family: Properties.fontFamily
        }
    }
}
