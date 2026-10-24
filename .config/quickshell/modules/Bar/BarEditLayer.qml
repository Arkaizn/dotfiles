import QtQuick
import qs.components
import qs.services

// Live editing of the bar (EditMode "bar"): sits on top of the modules of one
// bar; − takes one off, drag moves it. The dragged module follows the pointer
// freely (the bar's surface covers the screen while editing) and snaps to the
// nearest spot of the nearest zone when let go — dropped on the toolbar it
// leaves the bar. Modules from the toolbar are dragged on the same way.
// While dragging, every zone shows where it can go (DropZone) and a line
// marks the spot. (The wiggle itself: BarSection.)
Item {
    id: editor

    property string screenName
    property var sections: []           // the five BarSections of this bar
    property Item overlay: null         // full-window item for the ghost
    property Item toolbar: null         // BarEditToolbar (dropping there hides)

    readonly property bool editing: EditMode.target === "bar" && EditMode.screen === screenName
    // positions are along the bar: x on a top / bottom bar, y on a left / right one
    readonly property bool vertical: PanelGeometry.barVertical
    // the layout being edited: this monitor's own one, or the shared one
    readonly property string editScreen: BarLayout.hasOwn(screenName) ? screenName : ""

    visible: editing
    onEditingChanged: if (!editing) cancel()

    // placed, but not showing right now (no battery, nothing playing, …): the toolbar lists them
    readonly property var stateHidden: {
        const out = []
        for (const s of sections) {
            s.rev
            for (let i = 0; i < s.ids.length; i++) {
                const it = s.itemAt(i)
                if (it && !it.visible) out.push(s.ids[i])
            }
        }
        return out
    }

    // ── drag state ──────────────────────────────────────────────────────────
    property string dragId: ""
    property Item dragItem: null
    property point grab: Qt.point(0, 0)
    property point pointer: Qt.point(0, 0)  // overlay coordinates
    property real dragX: 0                  // along the bar, editor coordinates
    property string dropZone: ""            // "" = nowhere yet, "hide", or a zone
    property int dropIndex: 0

    function begin(id, item, gx, gy) {
        dragId = id
        dragItem = item
        grab = Qt.point(gx, gy)
        dropZone = ""
        EditMode.dragging = true
    }
    function cancel() {
        dragId = ""
        dragItem = null
        dropZone = ""
        EditMode.dragging = false
    }
    function finish() {
        if (dragId !== "" && dropZone === "hide") BarLayout.move(editScreen, dragId, "", 0)
        else if (dragId !== "" && dropZone !== "") BarLayout.move(editScreen, dragId, dropZone, dropIndex)
        cancel()
    }

    function sectionOf(zone) { return sections.find(s => s.zone === zone) ?? null }
    // start / length of an item along the bar
    function leftOf(item) { const p = item.mapToItem(editor, 0, 0); return vertical ? p.y : p.x }
    function lenOf(item) { return vertical ? item.height : item.width }

    // drop boxes per zone, in editor coordinates; empty zones still get a box
    readonly property real minBox: 40
    readonly property real pad: 4
    readonly property var boxes: {
        const out = {}
        const g = {}
        for (const s of sections) {
            s.x; s.y; s.width; s.height; editor.width; editor.height    // dependencies
            g[s.zone] = { x: leftOf(s), w: lenOf(s) }
        }
        if (!g.left || !g.right || !g.center || !g.centerLeft || !g.centerRight) return out
        const bw = w => Math.max(w, minBox) + pad * 2
        out.left = { x0: g.left.x - pad, x1: g.left.x - pad + bw(g.left.w) }
        out.right = { x1: g.right.x + g.right.w + pad, x0: g.right.x + g.right.w + pad - bw(g.right.w) }
        const cx = g.center.x + g.center.w / 2
        out.center = { x0: cx - bw(g.center.w) / 2, x1: cx + bw(g.center.w) / 2 }
        const clR = Math.min(g.centerLeft.x + g.centerLeft.w + pad, out.center.x0 - 3)
        out.centerLeft = { x0: clR - bw(g.centerLeft.w), x1: clR }
        const crL = Math.max(g.centerRight.x - pad, out.center.x1 + 3)
        out.centerRight = { x0: crL, x1: crL + bw(g.centerRight.w) }
        return out
    }

    // pointer moved (overlay coordinates): the ghost follows, the drop spot snaps
    function track(p) {
        pointer = p
        if (toolbar && toolbar.visible) {
            const t = toolbar.mapFromItem(overlay, p.x, p.y)
            if (t.x >= 0 && t.y >= 0 && t.x <= toolbar.width && t.y <= toolbar.height) { dropZone = "hide"; return }
        }
        const ep = editor.mapFromItem(overlay, p.x, p.y)
        const px = vertical ? ep.y : ep.x
        dragX = px
        let zone = "", best = 1e9
        for (const z of BarLayout.zones) {
            const b = boxes[z]
            if (!b) continue
            const d = px < b.x0 ? b.x0 - px : px > b.x1 ? px - b.x1 : 0
            if (d < best) { best = d; zone = z }
        }
        const sec = sectionOf(zone)
        if (!sec) return
        let idx = 0, pos = 0
        for (let i = 0; i < sec.ids.length; i++) {
            if (sec.ids[i] === dragId) continue
            const it = sec.itemAt(i)
            if (it && it.visible && leftOf(it) + lenOf(it) / 2 < px) idx = pos + 1
            pos++
        }
        dropZone = zone
        dropIndex = idx
    }

    // x of the drop marker
    readonly property real markerX: {
        dragX; dropIndex
        const sec = sectionOf(dropZone)
        const b = boxes[dropZone]
        if (!sec || !b) return 0
        let pos = 0, last = null
        for (let i = 0; i < sec.ids.length; i++) {
            if (sec.ids[i] === dragId) continue
            const it = sec.itemAt(i)
            if (it && it.visible) {
                if (pos >= dropIndex) return leftOf(it) - Properties.spacing / 2
                last = it
            }
            pos++
        }
        return last ? leftOf(last) + lenOf(last) + Properties.spacing / 2 : (b.x0 + b.x1) / 2
    }

    // where the dragged module would land (its top-left, overlay coordinates):
    // the ghost is pulled there near it (DragGhost magnet)
    readonly property var slot: {
        if (dragId === "" || !dragItem || dropZone === "" || dropZone === "hide" || !overlay) return null
        const p = vertical ? editor.mapToItem(overlay, (editor.width - dragItem.width) / 2, markerX + Properties.spacing / 2)
                           : editor.mapToItem(overlay, markerX + Properties.spacing / 2, (editor.height - dragItem.height) / 2)
        return { x: p.x, y: p.y }
    }

    // tap on an empty spot ends editing (like tapping the home screen background);
    // only a real tap — a press that moves (a drag that just missed a module) doesn't
    MouseArea {
        anchors.fill: parent
        enabled: editor.dragId === ""
        property point press: Qt.point(0, 0)
        onPressed: m => press = Qt.point(m.x, m.y)
        onClicked: m => { if (Math.hypot(m.x - press.x, m.y - press.y) <= 4) EditMode.stop() }
    }

    // ── drop zones (only while dragging) ────────────────────────────────────
    Repeater {
        model: BarLayout.zones
        DropZone {
            required property string modelData
            readonly property var box: editor.boxes[modelData] ?? { x0: 0, x1: 0 }
            x: editor.vertical ? 6 : box.x0
            width: editor.vertical ? editor.width - 12 : box.x1 - box.x0
            y: editor.vertical ? box.x0 : 6
            height: editor.vertical ? box.x1 - box.x0 : editor.height - 12
            radius: 9
            hot: editor.dropZone === modelData
            shown: editor.dragId !== ""
        }
    }

    Rectangle {
        visible: editor.dragId !== "" && editor.dropZone !== "" && editor.dropZone !== "hide"
        x: editor.vertical ? 10 : editor.markerX - 1.5
        y: editor.vertical ? editor.markerX - 1.5 : 10
        width: editor.vertical ? editor.width - 20 : 3
        height: editor.vertical ? 3 : editor.height - 20
        radius: 1.5
        color: Colors.color6
    }

    // ── one handle per module ───────────────────────────────────────────────
    Repeater {
        model: editor.sections
        Item {
            id: secHandles
            required property var modelData
            readonly property Item sec: modelData
            anchors.fill: parent

            Repeater {
                model: secHandles.sec.ids
                Item {
                    id: h
                    required property string modelData
                    required property int index
                    readonly property Item mod: { secHandles.sec.rev; return secHandles.sec.itemAt(index) }
                    readonly property bool dragged: editor.dragId === modelData

                    visible: mod !== null && mod.visible
                    x: { if (!mod) return 0; secHandles.sec.x; secHandles.sec.y; secHandles.sec.width; mod.x; mod.y; mod.width; return mod.mapToItem(editor, 0, 0).x }
                    y: { if (!mod) return 0; secHandles.sec.y; mod.y; mod.height; return mod.mapToItem(editor, 0, 0).y }
                    width: mod?.width ?? 0
                    height: mod?.height ?? 0
                    rotation: mod?.rotation ?? 0       // the badge wiggles along

                    // grabs a bit more than the module: half the gap to each
                    // neighbour and the bar's full thickness, so a press next to a
                    // (wiggling) module still drags it instead of hitting the bar
                    MouseArea {
                        x: editor.vertical ? -h.x : -Properties.spacing / 2 - 2
                        y: editor.vertical ? -Properties.spacing / 2 - 2 : -h.y
                        width: editor.vertical ? editor.width : parent.width + Properties.spacing + 4
                        height: editor.vertical ? parent.height + Properties.spacing + 4 : editor.height
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: h.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point press: Qt.point(0, 0)
                        onPressed: m => press = Qt.point(m.x, m.y)
                        onPositionChanged: m => {
                            if (!pressed) return
                            if (editor.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 4)
                                editor.begin(h.modelData, h.mod, press.x + x, press.y + y)   // grab point on the module
                            if (h.dragged) editor.track(mapToItem(editor.overlay, m.x, m.y))
                        }
                        onReleased: editor.finish()
                        onCanceled: editor.cancel()
                    }

                    EditBadge {
                        x: -6
                        y: -4
                        visible: editor.dragId === ""
                        onClicked: BarLayout.move(editor.editScreen, h.modelData, "", 0)
                    }
                }
            }
        }
    }

    // the dragged module follows the pointer, anywhere on the screen
    DragGhost {
        parent: editor.overlay
        source: editor.dragItem
        pointer: editor.pointer
        grab: editor.grab
        slot: editor.slot
    }
}
