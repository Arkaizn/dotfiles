import QtQuick
import qs.services.lib

// The part being dragged while editing a layout live: a live picture of it
// that follows the pointer (anywhere in the window it's put in — use the
// popup's / bar's full-screen overlay so it isn't clipped to the panel).
//   DragGhost { parent: overlay; source: dragItem; pointer: p; grab: g; slot: s }
//
// Magnet: `slot` is where the part would land (its top-left, in the parent's
// coordinates, or null). Near it the ghost is pulled in (Snap.pull) while
// still held, so it "clicks in" without feeling stuck: moving on pulls it
// out again.
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

    // follows the pointer 1:1 (Snap.pull already eases the magnet in); only
    // when the slot jumps to another spot does it glide over, briefly — a
    // spring on every move made the ghost trail and overshoot the pointer
    property bool _glide: false
    property real _sx: NaN
    property real _sy: NaN
    onSlotChanged: {
        const sx = slot ? slot.x : NaN, sy = slot ? slot.y : NaN
        // the slot is a new object on every pointer move: only a real move counts
        if (sx === _sx && sy === _sy) return
        const near = (x, y) => Math.hypot(x - free.x, y - free.y) < magnet   // NaN → false
        if (source && !(Math.abs(sx - _sx) < 1 && Math.abs(sy - _sy) < 1) && (near(sx, sy) || near(_sx, _sy))) {
            _glide = true
            glideEnd.restart()
        }
        _sx = sx; _sy = sy
    }
    onSourceChanged: { _glide = false; _sx = NaN; _sy = NaN }
    Timer { id: glideEnd; interval: 120; onTriggered: ghost._glide = false }
    Behavior on x { enabled: ghost._glide; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: ghost._glide; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
}
