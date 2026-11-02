import QtQuick
import QtQuick.Controls
import qs.services

// The shell's tooltip: a small popover above the control after a short
// hover. Pressable shows one for `tooltip`; anything else adds
//   HoverTip { text: "What this does"; shown: area.containsMouse }
ToolTip {
    id: tip

    property bool shown: false

    visible: shown && text !== ""

    // Never cover the control (that would eat the click): sit above it, or
    // below when the window has no room above (e.g. a close button at the top).
    readonly property int gap: Tokens.space.s6
    readonly property real ownerTop: {
        void tip.visible; void tip.implicitHeight; // re-map whenever it opens/resizes
        const p = tip.parent;
        return p ? p.mapToItem(null, 0, 0).y : 0;
    }
    x: tip.parent ? Math.round((tip.parent.width - tip.implicitWidth) / 2) : 0
    y: ownerTop >= tip.implicitHeight + gap
        ? -tip.implicitHeight - gap
        : (tip.parent ? tip.parent.height : 0) + gap
    delay: Anim.tooltipDelay
    timeout: -1
    padding: Tokens.space.s6
    leftPadding: Tokens.space.s10
    rightPadding: Tokens.space.s10
    // fade, not the default style's pop
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.slower; easing.type: Anim.standard } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Anim.instant; easing.type: Anim.exit } }

    contentItem: Text {
        text: tip.text
        color: Colors.textStrong
        font.pixelSize: Tokens.font.small
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }
    background: Rectangle {
        radius: Tokens.radius.md
        color: Colors.surfacePopover
        border.width: Tokens.border.thin
        border.color: Colors.lineSubtle
    }
}
