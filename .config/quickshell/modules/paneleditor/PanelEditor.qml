pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings/network"

// The panel editor (Part 6.8; EditMode "panels"): the bar and the big panels
// as outlines where they'd show. Drag the bar to another screen edge, drag a
// panel along the bar (it clicks into its start / centre / end) or away from
// it (it floats: raster + screen centre / edges / other panels), grips resize.
// Everything glides with a spring, also while still held; nothing lights up.
// Saved on release to Settings.panels (PanelGeometry), so the settings app,
// profiles and export / import see it.
//   qs ipc call edit panels · Settings → Panel editor → Edit live · bar edit toolbar
PanelWindow {
    id: ed

    screen: Quickshell.screens.find(s => s.name === EditMode.screen) ?? Quickshell.screens[0]
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:panel-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property var s: ({ w: width, h: height })
    readonly property int barT: liveThickness > 0 ? liveThickness : PanelGeometry.barThickness
    readonly property int gap: PanelGeometry.barGap
    readonly property int inset: Properties.barInset
    readonly property int flare: Properties.flareRadius
    readonly property int step: 8          // raster
    readonly property int snapDist: 12     // guides
    readonly property int magnet: 48       // start / centre / end of the bar
    readonly property int floatAt: 90      // this far off the bar a panel floats

    // ── live state (while something is dragged), saved on release ──
    property string drag: ""               // "" | "bar" | a panel id
    property string liveEdge: ""
    property int liveThickness: 0
    property var livePlace: ({})           // id → { attach, along, x, y }
    property var liveSize: ({})            // id → { w, h }
    property point grab: Qt.point(0, 0)    // pointer inside the dragged outline
    property string view: "apps"           // the launcher view shown / resized

    readonly property string edge: liveEdge !== "" ? liveEdge : PanelGeometry.barEdge
    readonly property var barR: EdgeMap.barRect(s, { edge: edge, thickness: barT, gap: gap, inset: inset })

    readonly property var panelIds: ["dashboard", "controlCenter", "launcher"]
    readonly property var names: ({ dashboard: "Dashboard", controlCenter: "Control center", launcher: "Launcher" })
    readonly property var icons: ({ dashboard: "󰕮", controlCenter: "󰒓", launcher: "󰀻" })

    // the launcher's chrome around its list (search field, mode bar, margins)
    readonly property int launcherChrome: Properties.buttonHeight * 2 + 16 + 42
    function sizeOf(id) {
        const l = liveSize[id]
        if (id === "dashboard")
            return { w: l?.w ?? PanelGeometry.dashboard.width,
                     h: (l?.h ?? Math.max(PanelLayout.dashHeight, PanelGeometry.dashboard.height)) + 20 }
        if (id === "controlCenter")
            return { w: l?.w ?? PanelGeometry.controlCenter.width, h: Math.min(s.h - 100, 760) }
        const v = PanelGeometry.launcherView(view)
        return { w: l?.w ?? v.w, h: (l?.h ?? v.h) + launcherChrome }
    }
    function placeOf(id) { return livePlace[id] ?? PanelGeometry.panel(id) }
    // the edge a panel hangs from, and how far from it (the bar, or a bare screen edge)
    function hangOf(id, p) {
        if (id === "launcher" && p.attach !== "bar") return { edge: EdgeMap.opposite(edge), offset: 0 }
        return { edge: edge, offset: gap + barT }
    }
    function rectOf(id) {
        const p = placeOf(id), z = sizeOf(id)
        if (p.attach === "float") return EdgeMap.panelRect(s, z.w, z.h, { float: true, x: p.x, y: p.y })
        const hg = hangOf(id, p)
        return EdgeMap.panelRect(s, z.w, z.h, { edge: hg.edge, offset: hg.offset, along: p.along, flare: flare, inset: inset })
    }

    function setLive(prop, id, v) { const o = Object.assign({}, ed[prop]); o[id] = v; ed[prop] = o }
    function clearLive() { drag = ""; liveEdge = ""; liveThickness = 0; livePlace = ({}); liveSize = ({}) }

    // a panel dragged with its top-left at (x, y): attached along an edge, or floating
    function placeAt(id, x, y) {
        const z = sizeOf(id), cx = x + z.w / 2, cy = y + z.h / 2
        const canon = (e) => EdgeMap.toCanon(e, z.w, z.h)
        if (id === "launcher") {
            // the bar's side or the opposite screen edge, whichever it's nearer
            const onBar = EdgeMap.depthOf(s, edge, cx, cy) < EdgeMap.depthOf(s, EdgeMap.opposite(edge), cx, cy)
            const e = onBar ? edge : EdgeMap.opposite(edge)
            return { attach: onBar ? "bar" : "edge", along: EdgeMap.alongAt(s, e, cx, cy, canon(e).along, inset, flare, magnet, step), x: 0.5, y: 0.5 }
        }
        const near = EdgeMap.depthOf(s, edge, cx, cy) - canon(edge).depth / 2 - (gap + barT)
        if (near < floatAt)
            return { attach: "bar", along: EdgeMap.alongAt(s, edge, cx, cy, canon(edge).along, inset, flare, magnet, step), x: 0.5, y: 0.5 }
        // floating: raster, screen centre / edges, the other panels' edges and centres
        const g = Snap.screenGuides(s.w, s.h, inset)
        for (const o of panelIds) {
            if (o === id) continue
            const r = rectOf(o)
            g.x.push(r.x, r.x + r.w / 2, r.x + r.w); g.y.push(r.y, r.y + r.h / 2, r.y + r.h)
        }
        const r = Snap.snapRect({ x: x, y: y, w: z.w, h: z.h }, g, snapDist, step)
        return { attach: "float", along: "center",
                 x: Math.round((r.x + z.w / 2) / s.w * 1000) / 1000, y: Math.round((r.y + z.h / 2) / s.h * 1000) / 1000 }
    }

    function save(id) {
        const p = livePlace[id]
        if (p) {
            PanelGeometry.set(id, "attach", p.attach)
            PanelGeometry.set(id, "along", p.along)
            if (p.attach === "float") { PanelGeometry.set(id, "x", p.x); PanelGeometry.set(id, "y", p.y) }
        }
        // only what was dragged (a width grip leaves the height alone)
        const z = liveSize[id]
        if (!z) return
        if (id === "dashboard") {
            if (z.w !== undefined) PanelGeometry.set("dashboard", "width", z.w)
            if (z.h !== undefined) PanelGeometry.set("dashboard", "height", z.h <= PanelLayout.dashHeight ? 0 : z.h)
        } else if (id === "controlCenter") {
            if (z.w !== undefined) PanelGeometry.set("controlCenter", "width", z.w)
        } else {
            const v = PanelGeometry.launcherView(view)
            PanelGeometry.setView(view, z.w ?? v.w, z.h ?? v.h)
        }
    }

    // ── canvas ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.38)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
    // a tap on an empty spot does nothing (Esc / Done close); keys
    MouseArea { anchors.fill: parent }
    Item {
        focus: true
        Keys.onEscapePressed: EditMode.stop()
    }

    // spring of every outline: glides to where it'd be, also while held
    component Glide: SpringAnimation { spring: 2.6; damping: 0.4; epsilon: 0.25 }

    // ── the bar ─────────────────────────────────────────────────────────────
    Rectangle {
        id: barGhost
        x: ed.barR.x; y: ed.barR.y; width: ed.barR.w; height: ed.barR.h
        Behavior on x { Glide {} }
        Behavior on y { Glide {} }
        Behavior on width { Glide {} }
        Behavior on height { Glide {} }
        radius: Properties.barRadius
        color: Properties.panelColor
        border.width: Math.max(1, Properties.panelBorderWidth)
        border.color: Properties.panelBorder
        scale: barArea.pressed ? 1.01 : 1
        Behavior on scale { NumberAnimation { duration: 160 } }

        Text {
            anchors.centerIn: parent
            rotation: EdgeMap.vertical(ed.edge) ? 90 : 0
            text: "󰍜  Bar · drag it to another edge"
            color: Colors.ink
            font { pixelSize: 13; family: Properties.fontFamily; bold: true }
        }
        MouseArea {
            id: barArea
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            onPressed: ed.drag = "bar"
            onPositionChanged: m => {
                if (!pressed) return
                const p = mapToItem(null, m.x, m.y)
                ed.liveEdge = Snap.nearestEdge(p.x, p.y, ed.s.w, ed.s.h)
            }
            onReleased: {
                if (ed.liveEdge !== "" && ed.liveEdge !== PanelGeometry.barEdge) PanelGeometry.set("bar", "edge", ed.liveEdge)
                ed.clearLive()
            }
            onCanceled: ed.clearLive()
        }

        // thickness grip on its inner side
        ResizeHandle {
            visible: ed.drag === "" || ed.drag === "bar-t"
            horizontal: EdgeMap.vertical(ed.edge)
            sign: ed.edge === "bottom" || ed.edge === "right" ? -1 : 1
            x: ed.edge === "left" ? parent.width - width / 2 : ed.edge === "right" ? -width / 2 : (parent.width - width) / 2
            y: ed.edge === "top" ? parent.height - height / 2 : ed.edge === "bottom" ? -height / 2 : (parent.height - height) / 2
            property int start: 0
            onStarted: { start = PanelGeometry.barThickness; ed.drag = "bar-t" }
            onMoved: d => ed.liveThickness = Snap.resize(start, d, PanelGeometry.limits["bar.thickness"][0], PanelGeometry.limits["bar.thickness"][1], 2)
            onDone: { if (ed.liveThickness > 0) PanelGeometry.set("bar", "thickness", ed.liveThickness); ed.clearLive() }
        }
    }

    // ── the panels ──────────────────────────────────────────────────────────
    Repeater {
        model: ed.panelIds
        Rectangle {
            id: ghost
            required property string modelData
            readonly property string pid: modelData
            readonly property var r: ed.rectOf(pid)
            readonly property var place: ed.placeOf(pid)
            readonly property bool floating: place.attach === "float"
            readonly property bool dragged: ed.drag === pid
            x: r.x; y: r.y; width: r.w; height: r.h
            Behavior on x { Glide {} }
            Behavior on y { Glide {} }
            Behavior on width { Glide {} }
            Behavior on height { Glide {} }
            z: dragged ? 5 : 1
            radius: Properties.panelRadius
            color: Qt.rgba(Properties.panelColor.r, Properties.panelColor.g, Properties.panelColor.b, 0.82)
            border.width: Math.max(1, Properties.panelBorderWidth)
            border.color: Properties.panelBorder
            scale: dragged ? 1.015 : 1
            Behavior on scale { NumberAnimation { duration: 160 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: ed.icons[ghost.pid] + "  " + ed.names[ghost.pid] + (ghost.pid === "launcher" ? " · " + ed.view : "")
                    color: Colors.ink
                    font { pixelSize: 15; family: Properties.fontFamily; bold: true }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(ghost.r.w) + " × " + Math.round(ghost.r.h - (ghost.pid === "launcher" ? ed.launcherChrome : ghost.pid === "dashboard" ? 20 : 0))
                          + "  ·  " + (ghost.floating ? "floating" : ghost.place.attach === "edge" ? "screen edge" : "on the bar")
                          + (ghost.floating ? "" : " · " + (typeof ghost.place.along === "number" ? Math.round(ghost.place.along * 100) + " %" : ghost.place.along))
                    color: Colors.fade(0.6)
                    font { pixelSize: 11; family: Properties.fontFamily }
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: 14              // the grips sit on the edges
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                onPressed: m => { ed.grab = Qt.point(m.x + anchors.margins, m.y + anchors.margins); ed.drag = ghost.pid }
                onPositionChanged: m => {
                    if (!pressed) return
                    const p = mapToItem(null, m.x, m.y)
                    ed.setLive("livePlace", ghost.pid, ed.placeAt(ghost.pid, p.x - ed.grab.x, p.y - ed.grab.y))
                }
                onReleased: { ed.save(ghost.pid); ed.clearLive() }
                onCanceled: ed.clearLive()
            }

            // grips: width on the right (left on a right bar), height at the bottom
            // (top on a bottom bar); centred panels grow to both sides
            readonly property bool centredH: floating || (!EdgeMap.vertical(ed.hangOf(pid, place).edge) && place.along === "center")
            readonly property bool centredV: floating || (EdgeMap.vertical(ed.hangOf(pid, place).edge) && place.along === "center")
            readonly property string hang: floating ? "" : ed.hangOf(pid, place).edge
            ResizeHandle {
                visible: ed.drag === "" || ed.drag === ghost.pid + "-w"
                horizontal: true
                sign: ghost.hang === "right" ? -1 : 1
                x: ghost.hang === "right" ? -width / 2 : parent.width - width / 2
                y: (parent.height - height) / 2
                property real start: 0
                onStarted: { start = ed.sizeOf(ghost.pid).w; ed.drag = ghost.pid + "-w" }
                onMoved: d => {
                    const lim = ghost.pid === "dashboard" ? PanelGeometry.limits["dashboard.width"]
                              : ghost.pid === "controlCenter" ? PanelGeometry.limits["controlCenter.width"] : PanelGeometry.limits["view.w"]
                    const cur = ed.liveSize[ghost.pid] ?? {}
                    ed.setLive("liveSize", ghost.pid, { w: Snap.resize(start, d * (ghost.centredH ? 2 : 1), lim[0], Math.min(lim[1], ed.s.w - 2 * ed.inset), 10),
                                                        h: cur.h })
                }
                onDone: { ed.save(ghost.pid); ed.clearLive() }
            }
            ResizeHandle {
                visible: ghost.pid !== "controlCenter" && (ed.drag === "" || ed.drag === ghost.pid + "-h")
                horizontal: false
                sign: ghost.hang === "bottom" ? -1 : 1
                x: (parent.width - width) / 2
                y: ghost.hang === "bottom" ? -height / 2 : parent.height - height / 2
                property real start: 0
                onStarted: {
                    start = ghost.pid === "dashboard" ? ed.sizeOf("dashboard").h - 20 : ed.sizeOf("launcher").h - ed.launcherChrome
                    ed.drag = ghost.pid + "-h"
                }
                onMoved: d => {
                    const lo = ghost.pid === "dashboard" ? PanelLayout.dashHeight : PanelGeometry.limits["view.h"][0]
                    const hi = ghost.pid === "dashboard" ? PanelGeometry.limits["dashboard.height"][1] : PanelGeometry.limits["view.h"][1]
                    const cur = ed.liveSize[ghost.pid] ?? {}
                    ed.setLive("liveSize", ghost.pid, { w: cur.w,
                                                        h: Snap.resize(start, d * (ghost.centredV ? 2 : 1), lo, Math.min(hi, ed.s.h - 160), 10) })
                }
                onDone: { ed.save(ghost.pid); ed.clearLive() }
            }
        }
    }

    // ── toolbar, in the middle of the screen ────────────────────────────────
    Rectangle {
        id: toolbar
        anchors.centerIn: parent
        width: tools.implicitWidth + 32
        height: tools.implicitHeight + 24
        radius: 18
        color: Properties.panelColor
        border.width: Math.max(1, Properties.panelBorderWidth)
        border.color: Properties.panelBorder
        z: 10
        opacity: ed.drag === "" ? 1 : 0.25
        Behavior on opacity { NumberAnimation { duration: 160 } }

        ColumnLayout {
            id: tools
            anchors.centerIn: parent
            spacing: 10
            RowLayout {
                spacing: 10
                Text {
                    text: "󰹑  Panel editor"
                    color: Colors.ink
                    font { pixelSize: 15; family: Properties.fontFamily; bold: true }
                }
                Item { Layout.fillWidth: true; Layout.minimumWidth: 20 }
                IconButton {
                    icon: "󰑓"
                    tooltip: "Everything back to the defaults"
                    interactive: PanelGeometry.changed
                    onClicked: PanelGeometry.reset()
                }
                IconButton {
                    icon: "󰄬"
                    tooltip: "Done (Esc)"
                    onClicked: EditMode.stop()
                }
            }
            Text {
                text: "Drag the bar to an edge · drag a panel along the bar, or off it to float · the grips resize"
                color: Colors.fade(0.6)
                font { pixelSize: 11; family: Properties.fontFamily }
            }
            RowLayout {
                spacing: 8
                Text {
                    text: "Launcher view"
                    color: Colors.fade(0.7)
                    font { pixelSize: 11; family: Properties.fontFamily }
                }
                Segmented {
                    small: true
                    options: [{ label: "Apps", value: "apps" }, { label: "Clipboard", value: "clipboard" }, { label: "Connections", value: "connections" },
                              { label: "Wallpapers", value: "wallpapers" }, { label: "Keybinds", value: "keybinds" }]
                    value: ed.view
                    onEdited: v => ed.view = v
                }
            }
        }
    }
}
