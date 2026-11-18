import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.lib

// The ground the pets of one monitor walk on: a layer surface as wide as the
// screen and only as high as a pet plus room for the hearts above it. It never
// takes the keyboard, and the pointer only where a pet is (the mask), so
// everything else under it is clicked as if it weren't there. Top layer: over
// windows, under fullscreen ones; "bottom" (a setting): on the desktop, like
// the widgets.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    WlrLayershell.layer: Pets.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.namespace: "quickshell:pets"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // stands on a bar at the bottom instead of covering it
    exclusiveZone: 0
    anchors { left: true; right: true; bottom: true }
    color: "transparent"

    readonly property int px: Pets.px
    // room above the tallest pet for what floats up from it (art pixels)
    readonly property int headroom: 14
    readonly property int tallest: Math.max(1, ...Pets.chosen.map(a => a.h))
    implicitHeight: (tallest + headroom) * px

    // only the pets take the pointer
    mask: Region { regions: win.petRegions }
    property var petRegions: []
    function collect() {
        const out = []
        for (let i = 0; i < pets.count; i++) { const p = pets.itemAt(i); if (p) out.push(p.region) }
        petRegions = out
    }

    Repeater {
        id: pets
        model: Pets.chosen
        Pet {
            required property var modelData
            required property int index
            def: modelData
            px: win.px
            ground: win.width
            y: win.height - height
            // spread out at the start, each on its own stretch
            start: (index + 0.5) / Math.max(1, pets.count)
            idle: Pets.idle
        }
        onItemAdded: win.collect()
        onItemRemoved: Qt.callLater(win.collect)
    }
}
