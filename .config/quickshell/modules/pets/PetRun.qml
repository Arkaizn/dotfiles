import QtQuick
import qs.services
import qs.services.lib

// The pets on the bar: they live in the same row as the bar's buttons, as high
// as a button, and rest in the free stretches between the button groups (so a
// sleeping cat never lies on the clock). The Bar loads this over its content
// (modules/bar/Bar.qml), only on a top / bottom bar; on a left / right bar, or
// with "at the bottom of the screen" chosen, PetStrip is used instead.
//
// It takes no clicks and no hover itself: only a pet does, in its own box.
// Everything else on the bar gets the pointer as if this weren't there.
Item {
    id: lane

    // the bar's groups of buttons (BarSection items), set by the Bar
    property var sections: []
    // as high as a button: whole screen pixels per art pixel
    readonly property int px: Math.max(1, Math.floor(PanelGeometry.barButtonHeight / 16))
    readonly property int petWidth: Math.max(1, ...Pets.chosen.map(a => a.w)) * px

    // Where the pointer is (x in here) while it's over the bar: the Bar tells us
    // (barX / barHovered, from its own HoverHandler). This item must not have a
    // hover handler or a mouse area of its own: it lies over the buttons, and an
    // item on top that takes hover leaves the buttons below without any (no hover
    // look, and a pressed button never springs back). Only a pet takes the pointer.
    property real barX: -1
    property bool barHovered: false
    property real dragX: -1
    readonly property real pointerX: held.running ? dragX : barX
    readonly property bool pointerKnown: barHovered || held.running
    // a pet being dragged says where the pointer is itself
    function pointAt(x) { dragX = x; held.restart() }
    Timer { id: held; interval: 600 }

    // [x0, x1] of every group that has buttons in it
    readonly property var taken: {
        const out = []
        for (const s of sections) {
            if (!s || !s.visible || s.width <= 1) continue
            s.x; s.parent?.x; lane.width            // (re-read when any of them moves)
            const p = s.mapToItem(lane, 0, 0)
            out.push([p.x, p.x + s.width])
        }
        return out
    }
    readonly property var spots: PetBrain.gaps(width, taken, petWidth, Tokens.space.s6)

    Repeater {
        id: pets
        model: Pets.chosen
        Pet {
            required property var modelData
            required property int index
            def: modelData
            px: lane.px
            run: lane
            ground: lane.width
            // feet on the buttons' bottom edge
            y: Math.round((lane.height + PanelGeometry.barButtonHeight) / 2) - height
            start: (index + 0.5) / Math.max(1, pets.count)
            idle: Pets.idle
        }
    }
}
