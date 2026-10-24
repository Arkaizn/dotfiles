import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.services.lib
import "outline.js" as Outline

// ── A popup that hangs from the bar ──
// Shared by the control center, dashboard and tray menu.
//
//   BarPopup {
//       side: "right"              // flush with the bar's end (right / bottom end)
//       panelWidth: 400            // the panel on screen (width × height),
//       panelHeight: col.implicitHeight + padding * 2   // whatever edge the bar is on
//       ipcName: "controlCenter"   // → qs ipc call controlCenter toggle
//       ColumnLayout { id: col; anchors { left: parent.left; right: parent.right } ... }
//   }
//
// Any bar edge (PanelGeometry.barEdge, Part 6.6): everything is laid out
// "canonically", as if it hung down from a bar at the top — u along the bar,
// v away from it — and mapped to the real edge (services/lib/EdgeMap.js). The
// outline gets the map as a matrix; the content is only moved, never rotated.
// So a panel on a left bar is still panelWidth wide and panelHeight high;
// along that bar it's panelHeight long.
//
// Shape: one outline drawn as a Shape — inverted ("flare") corners where it
// meets the bar, rounded far corners, and the shared panel border on every
// edge except the one it shares with the bar (the bar leaves a gap in its own
// border there, see BarState / Bar.qml).
//
// Open/close: the panel unrolls away from the bar (its depth animates), the
// content slides a little and fades in. The layer surface itself never
// resizes — only items inside it — so it stays smooth.
PanelWindow {
    id: root

    // ── Config ────────────────────────────────────────────────
    property string side: "right"      // "left" | "right" | "center" | "at" (left / right = the bar's start / end)
    property real atX: 0               // side "at": screen position along the bar the panel is centred on (clamped to the bar)
    property int panelWidth: 400
    property real panelHeight: 300     // fully open height, including padding
    property int maxHeight: Math.ceil(panelHeight) // most it grows to (height; along a vertical bar)
    property int padding: 10
    property bool autoClose: true      // close shortly after the pointer leaves
    property string ipcName: ""
    // its place along the bar from Settings.panels.<placeId> (PanelGeometry,
    // the panel editor): "start" | "center" | "end" | fraction; "" = `side` decides
    property string placeId: ""
    // live editing (EditMode): the surface covers the screen so a dragged part
    // can follow the pointer anywhere; only the panel takes input (mask)
    property bool fullscreen: false
    // above the panel, not clipped, window coordinates: for drag ghosts
    readonly property alias overlay: overlayItem
    // the panel's frame (unrolled part, incl. flares), for grips on its edges
    // (ResizeHandle); panelRect() = the panel itself in it, real coordinates
    readonly property alias frameItem: frame

    default property alias content: body.data

    // ── State ─────────────────────────────────────────────────
    property bool shown: false         // logical state; `visible` lags during the close animation
    property real reveal: 0            // 0 = closed, 1 = fully open
    property bool hasBeenHovered: false

    // Auto-close only counts down once the pointer is off the popup AND off
    // the bar on this screen (moving popup → bar keeps it open).
    readonly property bool _barHovered: BarState.hoveredBars[screen?.name ?? ""] === true
    on_BarHoveredChanged: _updateAutoClose()
    function _updateAutoClose() {
        if (!autoClose || !shown) return
        if (popupHover.hovered || _barHovered) autoCloseTimer.stop()
        else if (hasBeenHovered) autoCloseTimer.restart()
    }

    signal opening()
    signal popupClosed()

    // ── Edge + canonical sizes ────────────────────────────────
    // floating (the panel editor dragged it off the bar): anywhere on the screen,
    // all corners round, fades in; the maths below then runs as for a top bar
    readonly property bool floating: _place !== null && _place.attach === "float"
    readonly property string edge: floating ? "top" : PanelGeometry.barEdge
    readonly property bool vertical: EdgeMap.vertical(edge)
    readonly property real alongLen: vertical ? panelHeight : panelWidth    // along the bar
    readonly property real depthLen: vertical ? panelWidth : panelHeight    // away from it
    readonly property real screenAlong: EdgeMap.along(edge, screen?.width ?? 2560, screen?.height ?? 1440)
    readonly property real screenAcross: EdgeMap.across(edge, screen?.width ?? 2560, screen?.height ?? 1440)

    // where along the bar: `side`, or the panel editor's place (placeId). Flush
    // with an end of the bar (start / end, or a place that reaches it) = no
    // inverted corner on that side.
    readonly property var _place: placeId !== "" ? PanelGeometry.panel(placeId) : null
    readonly property var _along: _place ? _place.along : side === "left" ? "start" : side === "right" ? "end" : "center"
    readonly property int _free: EdgeMap.place(_along, alongLen + 2 * Properties.flareRadius, screenAlong, Properties.barInset)
    readonly property string placeSide: side === "at" ? "at"
        : _along === "start" || (_place && _free <= Properties.barInset) ? "left"
        : _along === "end" || (_place && _free >= screenAlong - Properties.barInset - alongLen - 2 * Properties.flareRadius) ? "right"
        : "center"
    readonly property int flareL: floating || placeSide === "left" ? 0 : Properties.flareRadius
    readonly property int flareR: floating || placeSide === "right" ? 0 : Properties.flareRadius

    // Current geometry — corners shrink with the panel so it never folds over itself
    readonly property real h: floating ? depthLen : depthLen * reveal   // depth unrolled now
    readonly property real r: Math.min(Properties.panelRadius, h / 2)
    // floating: where (its centre as a fraction of the screen, kept on it)
    readonly property real _sw: screen?.width ?? 2560
    readonly property real _sh: screen?.height ?? 1440
    // (always an object: bindings reading it can run before `floating` settles)
    readonly property var _floatRect: ({
        x: Math.round(Snap.clamp((_place?.x ?? 0.5) * _sw - panelWidth / 2, 0, _sw - panelWidth)),
        y: Math.round(Snap.clamp((_place?.y ?? 0.5) * _sh - panelHeight / 2, 0, _sh - panelHeight)),
        w: panelWidth, h: Math.ceil(panelHeight) })
    readonly property real fl: Math.min(flareL, Math.max(0, h - r))
    readonly property real fr: Math.min(flareR, Math.max(0, h - r))

    visible: false
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: floating ? ExclusionMode.Ignore : ExclusionMode.Normal
    // The surface spans the whole edge (floating: the screen); the panel moves
    // inside it (`ox`), so moving to a new spot is an animation, not a surface resize.
    anchors {
        top: floating || EdgeMap.anchors(edge).top
        bottom: floating || EdgeMap.anchors(edge).bottom
        left: floating || EdgeMap.anchors(edge).left
        right: floating || EdgeMap.anchors(edge).right
    }
    // the surface's depth: the most the panel needs, or nearly the screen while editing
    readonly property int surfDepth: fullscreen ? Math.max(depthMax, screenAcross - 80) : depthMax
    readonly property int depthMax: vertical ? panelWidth : maxHeight
    implicitWidth: vertical ? surfDepth : 0
    implicitHeight: vertical ? 0 : surfDepth
    // along the bar: the panel + its flares
    readonly property real implicitAlong: alongLen + flareL + flareR

    // ── API ───────────────────────────────────────────────────
    // `scr`: the screen whose bar was clicked (optional) — opens there.
    function toggle(scr) {
        if (shown && (!scr || scr === screen)) close()
        else open(scr)
    }

    function open(scr) {
        // No screen given (keybind / IPC): open on the focused output.
        if (!scr && !shown && (Compositor.isNiri || Compositor.isHyprland)) {
            Compositor.focusedOutput(name => {
                const s = Quickshell.screens.find(x => x.name === name)
                root.open(s ?? root.screen ?? Quickshell.screens[0])
            })
            return
        }
        if (scr && scr !== screen) {
            BarState.detach(_id)
            screen = scr
        }
        if (!screen) screen = Quickshell.screens[0]
        closeAnim.stop()
        autoCloseTimer.stop()
        hasBeenHovered = false
        shown = true
        visible = true
        _attach()
        opening()
        openAnim.start()
    }

    function close() {
        if (!shown) return
        shown = false
        openAnim.stop()
        autoCloseTimer.stop()
        closeAnim.start()
    }

    // the panel (without flares) in frameItem, real coordinates: for grips
    function panelRect() { return EdgeMap.mapRect(edge, h, flareL, 0, alongLen, h) }

    // ── Internals ─────────────────────────────────────────────
    readonly property string _id: "barpopup:" + (ipcName || String(root))

    // side "at": start of the panel (incl. flares) along the bar, kept on the bar
    readonly property int _atLeft: {
        const x = Math.round(atX - implicitAlong / 2)
        return Math.max(Properties.barInset, Math.min(screenAlong - Properties.barInset - implicitAlong, x))
    }
    // where the panel sits on its own (start / end / center of the bar, or its place)
    readonly property int _fixedLeft: placeSide === "left" ? Properties.barInset
                                    : placeSide === "right" ? screenAlong - Properties.barInset - implicitAlong
                                    : _place ? _free
                                    : Math.floor((screenAlong - implicitAlong) / 2)

    // start of the panel (incl. flares) along the surface; animates for side "at"
    // and while the panel editor moves it
    property real ox: side === "at" ? _atLeft : _fixedLeft
    Behavior on ox {
        enabled: root.shown && (root.side === "at" || root.placeId !== "")
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    onOxChanged: if (shown) _attach()

    function _attach() {
        const s = screen
        if (!s) return
        if (floating) { BarState.detach(_id); return }
        BarState.attach(_id, s.name, ox, ox + implicitAlong, placeSide)
    }

    onImplicitAlongChanged: if (shown) _attach()
    onFloatingChanged: if (shown) _attach()

    NumberAnimation {
        id: openAnim
        target: root; property: "reveal"; to: 1
        duration: 300; easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: root; property: "reveal"; to: 0
        duration: 200; easing.type: Easing.InCubic
        onFinished: {
            if (root.shown) return
            root.visible = false
            BarState.detach(root._id)
            root.popupClosed()
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 500
        onTriggered: root.close()
    }

    IpcHandler {
        target: root.ipcName
        enabled: root.ipcName !== ""
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    // the same functions for the rest of the shell: Panels.toggle(ipcName, screen)
    readonly property var _panel: ({ toggle: scr => root.toggle(scr), open: scr => root.open(scr), close: () => root.close() })
    Component.onCompleted: if (ipcName !== "") Panels.register(ipcName, _panel)
    Component.onDestruction: Panels.unregister(ipcName, _panel)

    // ── Regions ───────────────────────────────────────────────
    mask: Region { item: frame }

    // canonical rectangle → surface rectangle (for the regions below)
    function _m(u, v, w, d) { return EdgeMap.mapRect(edge, surfDepth, u, v, w, d) }
    readonly property var _body: floating ? _floatRect : _m(ox + flareL, 0, alongLen, Math.ceil(h))
    readonly property var _bodyR: floating ? { tl: r, tr: r, br: r, bl: r }
                                           : EdgeMap.corners(edge, { outerStart: 0, outerEnd: 0, innerEnd: r, innerStart: r })
    readonly property var _flL: _m(ox + flareL - fl, 0, fl, fl)
    readonly property var _flLc: _m(ox + flareL - fl * 2, 0, fl * 2, fl * 2)
    readonly property var _flR: _m(ox + flareL + alongLen, 0, fr, fr)
    readonly property var _flRc: _m(ox + flareL + alongLen, 0, fr * 2, fr * 2)

    // Body (rounded far corners) + each flare = its square minus a circle,
    // so the inverted corners are blurred too.
    BackgroundEffect.blurRegion: Region {
        x: root._body.x; y: root._body.y
        width: root._body.w; height: root._body.h
        topLeftRadius: root._bodyR.tl; topRightRadius: root._bodyR.tr
        bottomRightRadius: root._bodyR.br; bottomLeftRadius: root._bodyR.bl

        Region {
            x: root._flL.x; y: root._flL.y
            width: root._flL.w; height: root._flL.h
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: root._flLc.x; y: root._flLc.y
                width: root._flLc.w; height: root._flLc.h
            }
        }
        Region {
            x: root._flR.x; y: root._flR.y
            width: root._flR.w; height: root._flR.h
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: root._flRc.x; y: root._flRc.y
                width: root._flRc.w; height: root._flRc.h
            }
        }
    }

    // ── Visuals ───────────────────────────────────────────────
    // the unrolled part (panel + flares), real coordinates; clips the content
    Item {
        id: frame
        readonly property var g: root.floating ? root._floatRect : root._m(root.ox, 0, root.implicitAlong, Math.ceil(root.h))
        x: g.x
        y: g.y
        width: g.w
        height: g.h
        clip: true
        // floating: fades and grows in instead of unrolling
        opacity: root.floating ? root.reveal : 1
        scale: root.floating ? 0.96 + 0.04 * root.reveal : 1

        HoverHandler {
            id: popupHover
            enabled: root.autoClose
            onHoveredChanged: {
                if (hovered) root.hasBeenHovered = true
                root._updateAutoClose()
            }
        }

        // the outline, drawn canonically and mapped to the edge
        Item {
            width: root.implicitAlong
            height: root.h
            transform: Matrix4x4 { matrix: EdgeMap.qmatrix(EdgeMap.matrix(root.edge, root.h)) }

            Shape {
                id: shape
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                readonly property string outline: root.floating
                    ? Outline.rounded(root.panelWidth, root.h, root.r, Properties.panelBorderWidth / 2)
                    : Outline.panel(root.flareL, root.flareL + root.alongLen, root.h,
                                    root.fl, root.fr, root.r, Properties.panelBorderWidth / 2)

                ShapePath {
                    fillColor: Properties.panelColor
                    strokeColor: "transparent"
                    PathSvg { path: root.floating ? shape.outline : shape.outline + "Z" }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Properties.panelBorder
                    strokeWidth: Properties.panelBorderWidth
                    PathSvg { path: shape.outline }
                }
            }
        }

        // Content: slides away from the bar a bit and fades in as the panel unrolls
        Item {
            id: body
            readonly property var g: EdgeMap.mapRect(root.edge, root.h, root.flareL + root.padding,
                                                     root.padding - (1 - root.reveal) * 24,
                                                     root.alongLen - root.padding * 2, root.depthLen - root.padding * 2)
            x: g.x
            y: g.y
            width: g.w
            height: g.h
            opacity: Math.min(1, root.reveal * 1.5)
        }
    }

    Item {
        id: overlayItem
        anchors.fill: parent
        z: 10
    }
}
