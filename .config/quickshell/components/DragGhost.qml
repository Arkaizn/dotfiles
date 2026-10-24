import QtQuick
import qs.services.lib

// The part being dragged while editing a layout live: a live picture of it
// that follows the pointer (anywhere in the window it's put in — use the
// popup's / bar's full-screen overlay so it isn't clipped to the panel).
//   DragGhost { parent: overlay; source: dragItem; pointer: p; grab: g; slot: s }
//
// Magnet: `slot` is where the part would land (its top-left, in the parent's
// coordinates, or null). Near it the ghost is pulled in (Snap.pull) while
// still held, and it moves there with a slow spring, so it "clicks in"
// without feeling stuck: moving on pulls it out again.
ShaderEffectSource {
    id: ghost
    property Item source: null
    property point pointer: Qt.point(0, 0)   // in the parent's coordinates
    property point grab: Qt.point(0, 0)      // where the part was grabbed, inside it
    property var slot: null                  // { x, y } or null
    property real magnet: 70                 // pull radius (px)

    readonly property var free: ({ x: pointer.x - grab.x, y: pointer.y - grab.y })
    readonly property var goal: Snap.pull(free, slot, magnet)
    readonly property bool snapped: slot !== null && Math.hypot(goal.x - slot.x, goal.y - slot.y) < 1

    visible: source !== null
    sourceItem: source
    live: true
    hideSource: false
    z: 1000
    width: source?.width ?? 0
    height: source?.height ?? 0
    x: goal.x
    y: goal.y
    scale: snapped ? 1.0 : 1.06
    opacity: 0.94
    transformOrigin: Item.Center

    // no spring for the first frame of a drag (it would fly in from the last spot)
    property bool _armed: false
    onSourceChanged: { _armed = false; if (source) Qt.callLater(() => ghost._armed = true) }
    Behavior on x { enabled: ghost._armed; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.2 } }
    Behavior on y { enabled: ghost._armed; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.2 } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
}
