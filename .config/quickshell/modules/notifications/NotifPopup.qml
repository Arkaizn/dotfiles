import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// ── Popup manager ──
// One fixed-size layer surface holding a column of NotifPopupCard's.
//
// Previously every notification got its own PanelWindow whose height and
// margins animated — every frame of that is a Wayland surface reconfigure
// (same problem the Launcher comments describe), and the blur region was
// bound to an item that never moved, so the slide never looked right.
// Here the surface never changes; cards slide/collapse as ordinary items,
// and `mask` lets clicks fall through everywhere except on the cards.
PanelWindow {
    id: root

    visible: Notifs.popupModel.count > 0
    // Settings → Notifications → Position
    readonly property string position: Notifs.position
    readonly property bool atBottom: position.startsWith("bottom")
    readonly property bool atLeft: position.endsWith("left")
    readonly property bool atCenter: position.endsWith("center")
    anchors { top: !atBottom; bottom: atBottom; right: !atLeft && !atCenter; left: atLeft }
    margins { top: 6; bottom: 10; right: 10; left: 10 }
    implicitWidth: 380
    implicitHeight: 900
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifications"

    // Cards register their own blur Region here (see NotifPopupCard).
    // A Region with `item:` only follows that item's *own* geometry, not
    // its parents', so each card provides explicit window coordinates instead.
    property var cardRegions: []

    function addRegion(r) { cardRegions = cardRegions.concat([r]) }
    function removeRegion(r) { cardRegions = cardRegions.filter(x => x !== r) }

    BackgroundEffect.blurRegion: Region { regions: root.cardRegions }
    mask: Region { item: column }

    Column {
        id: column
        // anchored to the corner / edge from Settings (undefined = not anchored)
        width: 360
        anchors.top: root.atBottom ? undefined : parent.top
        anchors.bottom: root.atBottom ? parent.bottom : undefined
        anchors.right: root.atLeft || root.atCenter ? undefined : parent.right
        anchors.left: root.atLeft ? parent.left : undefined
        anchors.horizontalCenter: root.atCenter ? parent.horizontalCenter : undefined

        Repeater {
            model: Notifs.popupModel

            NotifPopupCard {
                width: column.width
                window: root
                xOffset: column.x
                yOffset: column.y
                side: root.atLeft ? -1 : 1
            }
        }
    }
}
