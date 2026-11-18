import Quickshell
import QtQuick
import qs.components
import qs.services
import qs.services.lib

// One pet, on the bar (PetRun) or on the strip at the bottom of the screen
// (PetStrip). What it does next comes from services/lib/PetBrain.js and its
// own nature (its definition, PetCat.js …): mostly it lies around or naps, now
// and then it gets up for a short walk. Click or drag it and it's called: it
// may follow the pointer for a while (the dog always, the cat when it likes),
// then it goes back to resting. A notification makes it look up.
//
// One timer drives it, and only while something changes: its step time while it
// moves, a slow beat while it breathes in its sleep, nothing at all while it
// just lies there or you're away. Its frames are images made once (PixelSprite),
// so showing another one costs nothing. With "Reduce motion" it stays where it
// is and holds its pose.
Item {
    id: root

    property var def                       // the animal (PixelArt.js format)
    property int px: 2
    property real ground: 0                // width it can walk on
    property real start: 0.5               // where it starts, 0…1 of the ground
    property bool idle: false              // the user is away
    // on the bar: PetRun (the pointer, the free places between the buttons); else null
    property var run: null
    readonly property var spots: run ? run.spots : []
    readonly property var nature: PetBrain.natureOf(def.nature)

    property string doing: "lie"           // PetBrain state
    property int dir: 1                    // 1 right, -1 left
    property int elapsed: 0                // ms in this state
    property int lasts: 4000               // ms this state takes (0 = until something happens)
    property string frame: PixelArt.frameAt(def, "lie", 0)
    property real goal: -1                 // a walk to a place to rest: where
    property var then: null                // … and what it does there
    property bool there: false             // following: it has reached the pointer

    // the pointer's share of the strip (PetStrip's mask)
    readonly property Region region: Region { item: root }

    width: def.w * px
    height: def.h * px
    readonly property real maxX: Math.max(0, ground - width)
    function snap(v) { return Math.round(v / px) * px }
    // until it has taken its first step it stays at `start`, in a free place if
    // there are any (the bar gets its width and buttons a moment after it's created)
    property bool walked: false
    function place() {
        if (!walked) x = snap(Math.min(maxX, PetBrain.nearestSpot(start * maxX, spots)))
        else if (x > maxX) x = snap(maxX)
    }
    onMaxXChanged: place()
    onSpotsChanged: place()

    readonly property bool canMove: Anim.ambient
    readonly property string anim: doing === "follow" ? (there || !canMove ? arriveAnim : "run") : (def.anims[doing] ? doing : "stand")
    readonly property string arriveAnim: nature.arrive === "sleep" ? "sit" : nature.arrive
    readonly property bool moving: canMove && (doing === "walk" || (doing === "follow" && !there))

    function enter(st, ms, d) {
        doing = st
        lasts = ms
        if (d) dir = d
        elapsed = 0
        there = false
        if (st !== "walk") { goal = -1; then = null }
        frame = PixelArt.frameAt(def, anim, 0)
    }
    function inSpot() { return spots.length === 0 || spots.some(s => x >= s[0] - px && x <= s[1] + px) }
    function advance() { settle(PetBrain.next(doing, { idle: idle, dir: dir, nature: def.nature }, Math.random)) }
    // start what comes next. On the bar it doesn't lie down on a button: it walks
    // to the nearest free place first
    function settle(n) {
        if (PetBrain.resting[n.state] && canMove && !inSpot()) {
            enter("walk", 20000, dir)
            goal = snap(PetBrain.nearestSpot(x, spots))
            then = n
        } else enter(n.state, n.ms, n.dir)
    }

    // called: clicked or dragged. Whether it comes is its nature.
    function called() {
        const r = PetBrain.called(def.nature, def.anims, Math.random)
        floatUp("heart", width / 2)
        if (r.state === "follow" && !run) { enter("happy", 2400, dir); return }      // nowhere to follow to (the strip)
        enter(r.state, r.ms, dir)
    }
    // a notification: look up for a moment
    function perk() {
        if (doing === "follow" || doing === "happy") return
        enter("alert", 1500, dir)
        floatUp("bang", width / 2)
    }

    onIdleChanged: {
        if (idle && doing !== "sleep" && doing !== "lie") advance()
        else if (!idle && doing === "sleep" && lasts === 0) advance()
    }

    Connections {
        target: Pets
        function onPoke() { root.perk() }
    }

    // Nothing ticks while nothing changes: a pet that lies or sits (one pose) only
    // wakes when that's over; one that sleeps while you're away doesn't wake at all
    // until you're back. Breathing in its sleep is slow; only moving is quick.
    readonly property var animNow: def.anims[anim]
    readonly property bool still: !moving && doing !== "follow" && (animNow.seq.length < 2 || !canMove || (doing === "sleep" && idle))
    Timer {
        id: tick
        interval: root.moving ? root.nature.stepMs
                : root.doing === "follow" ? 150
                : root.still ? Math.max(50, root.lasts - root.elapsed)
                : Math.max(60, root.animNow.ms * (root.doing === "sleep" ? 1.6 : 1))
        repeat: true
        running: root.visible === true && !(root.still && root.lasts === 0)
        onTriggered: {
            root.elapsed += interval
            const a = root.def.anims[root.anim]
            const steps = (a.move ? a.move[PixelArt.indexAt(root.def, root.anim, root.elapsed)] : 1) * root.px
            if (root.doing === "walk" && root.canMove) {
                root.walked = true
                if (root.goal >= 0) {
                    const t = PetBrain.toward(root.x, root.goal, steps, 0, root.maxX, 0)
                    root.x = t.x
                    root.dir = t.dir
                    if (t.there && steps > 0) { const n = root.then; root.enter(n.state, n.ms, n.dir); return }
                } else {
                    const w = PetBrain.walk(root.x, root.dir, steps, 0, root.maxX)
                    root.x = w.x
                    root.dir = w.dir
                }
            } else if (root.doing === "follow") {
                const known = root.run && root.run.pointerKnown
                if (known && root.canMove) {
                    root.walked = true
                    const t = PetBrain.toward(root.x, root.run.pointerX - root.width / 2, root.there ? 0 : steps, 0, root.maxX, root.there ? root.width * 0.8 : root.width * 0.25)
                    if (!root.there) { root.x = t.x; root.dir = t.dir }
                    else if (!t.there) root.dir = t.dir
                    if (t.there && !root.there) {
                        root.there = true
                        root.floatUp("heart", root.width / 2)
                        // the hamster: got there, out of breath, asleep
                        if (root.nature.arrive === "sleep") { root.settle({ state: "sleep", ms: PetBrain.between(root.nature.napMs, Math.random()), dir: root.dir }); return }
                    } else if (!t.there && root.there) root.there = false
                } else root.there = true            // the pointer is gone: it waits where it is
            }
            root.frame = PixelArt.frameAt(root.def, root.anim, root.canMove && !root.still ? root.elapsed : 0)
            if (root.lasts > 0 && root.elapsed >= root.lasts) root.advance()
        }
    }

    // asleep: a "z" drifts up now and then
    Timer {
        interval: 6000
        repeat: true
        running: root.visible === true && root.doing === "sleep" && Anim.ambient && !root.idle
        onTriggered: root.floatUp("z", root.dir > 0 ? root.width * 0.8 : root.width * 0.2)
    }

    function floatUp(kind, atX) {
        floaty.createObject(root, { kind: kind, px: Math.max(1, root.px - 1), startX: atX, startY: root.px * 2, steps: root.run ? 7 : 14 })
    }
    Component { id: floaty; PetFloaty {} }

    // the press you can feel: it squashes a little while held
    Pressable {
        id: touch
        anchors.fill: parent
        showFocusRing: false
        activeFocusOnTab: false
        accessibleName: "Call the " + root.def.name.toLowerCase()
        onClicked: root.called()

        PixelSprite {
            id: sprite
            rows: PixelArt.frame(root.def, root.frame)
            palette: Pets.paletteOf(root.def)
            px: root.px
            flipped: root.dir < 0
            transformOrigin: Item.Bottom
            scale: touch.pressed || drag.active ? Properties.onPressedButtonScale : 1
            Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }
        }
    }
    // dragged: it's called too, and the pointer it follows is the one that drags
    DragHandler {
        id: drag
        target: null
        onActiveChanged: if (active) root.called()
        onCentroidChanged: if (active && root.run) root.run.pointAt(root.mapToItem(root.run, centroid.position.x, 0).x)
    }
}
