import QtQuick

// The part being dragged while editing a layout live: a live picture of it
// that follows the pointer (anywhere in the window it's put in — use the
// popup's / bar's full-screen overlay so it isn't clipped to the panel).
//   DragGhost { parent: overlay; source: dragItem; pointer: p; grab: g }
ShaderEffectSource {
    id: ghost
    property Item source: null
    property point pointer: Qt.point(0, 0)   // in the parent's coordinates
    property point grab: Qt.point(0, 0)      // where the part was grabbed, inside it

    visible: source !== null
    sourceItem: source
    live: true
    hideSource: false
    z: 1000
    width: source?.width ?? 0
    height: source?.height ?? 0
    x: pointer.x - grab.x
    y: pointer.y - grab.y
    scale: 1.06
    opacity: 0.94
    transformOrigin: Item.Center
}
