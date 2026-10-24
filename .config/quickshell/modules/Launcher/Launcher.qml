import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
import qs.services.lib
import QtQuick.Effects
import QtQuick.Shapes
import "../../components/outline.js" as Outline

// ── Root of the launcher ──
// Owns the PanelWindow/layer-shell surface, the open/close slide animation,
// the shared search field, and the small mode-switcher (search vs
// clipboard). The actual result lists live in AppSearch.qml and
// ClipboardHistory.qml — this file just decides which one is showing and
// feeds them both the same search text.
PanelWindow {
    id: root
    visible: false

    // Which screen edge it comes from (Settings → Panel editor, Part 6.6):
    // "edge" = the one opposite the bar (bar on top → from the bottom, as it
    // always was), "bar" = out of the bar. The outline is drawn canonically (as
    // if it hung from the top, EdgeMap) and mapped to the real edge; the card
    // sits on that edge, at its place along it (Settings.panels.launcher.along).
    // The surface spans the whole edge (mask = the card), so moving the card
    // along it is an item animation, not a surface resize.
    readonly property string edge: PanelGeometry.launcher.attach === "bar" ? PanelGeometry.barEdge : EdgeMap.opposite(PanelGeometry.barEdge)
    readonly property bool vertical: EdgeMap.vertical(edge)
    anchors {
        top: edge === "top" || vertical
        bottom: edge === "bottom" || vertical
        left: edge === "left" || !vertical
        right: edge === "right" || !vertical
    }
    // card width (apps / clipboard; the wallpaper grid gets a wider card),
    // surface = the widest card + room for the inverted corners on both sides.
    // The surface keeps that width all the time (see the height note below);
    // only the visible card animates between the two widths.
    // each view has its own size (Settings → Panels → Launcher, PanelGeometry)
    function viewSize(v) { return PanelGeometry.launcherView(v) }
    readonly property int shownCardWidth: viewSize(mode).w
    readonly property int flare: Properties.flareRadius
    readonly property int widestView: Math.max(...modes.map(v => viewSize(v).w))
    implicitWidth: vertical ? widestView : 0

    // ── Why the surface size is a constant, not a binding ──
    // implicitHeight here drives the *real* Wayland layer-shell surface
    // (via WlrLayershell), not just a QtQuick item. Every time it changes,
    // Quickshell has to renegotiate a new surface size with the compositor.
    // That's fine once (e.g. on open), but animating it — or even just
    // letting it snap around every keystroke, or every time you switch
    // between the apps and clipboard views — causes visible desync:
    // ghosting, stale content bleeding through, UI elements briefly
    // rendered at the wrong position relative to the new bounds.
    //
    // The fix: make the surface a fixed size, big enough for the tallest
    // possible state across *both* views, and never touch it again while
    // the launcher is open. All the *visible* growing/shrinking happens on
    // `card` below instead — an ordinary Rectangle inside the surface,
    // animated with a plain `Behavior on height`. That's pure GPU-side
    // compositing, not a surface reconfigure, so it can animate as smoothly
    // as any other QtQuick property — including when switching modes.
    readonly property int tallestView: Math.max(...modes.map(v => viewSize(v).h))
    readonly property int contentSpacing: 8
    readonly property int modeBarHeight: Properties.buttonHeight
    readonly property int contentMargins: 16 + 26 // matches content's anchors.margins + bottomMargin below

    // tallest results list + search bar + mode-switcher row + the two gaps
    // between them (content always has exactly 3 visible children: one of
    // the two views, the search field, and the mode bar) + outer margins.
    readonly property int tallestCard: tallestView + contentSpacing * 2 + Properties.buttonHeight + modeBarHeight + contentMargins
    implicitHeight: vertical ? 0 : tallestCard
    // the surface across its edge (depth) and along it
    readonly property real surfDepth: vertical ? width : height
    readonly property real surfAlong: vertical ? height : width

    color: Colors.shade(0.0)
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0
    // out of the bar: sits right on it (the compositor doesn't move it past the
    // bar's zone by itself), and tells the bar, which opens its border there
    readonly property bool onBar: PanelGeometry.launcher.attach === "bar"
    exclusionMode: onBar ? ExclusionMode.Ignore : ExclusionMode.Normal
    readonly property int barOffset: onBar ? PanelGeometry.barGap + PanelGeometry.barThickness : 0
    margins {
        top: edge === "top" ? barOffset : 0
        bottom: edge === "bottom" ? barOffset : 0
        left: edge === "left" ? barOffset : 0
        right: edge === "right" ? barOffset : 0
    }
    readonly property string _barId: "launcher"
    function _attachBar() {
        if (!onBar || !visible || !screen) { BarState.detach(_barId); return }
        const a0 = cardU - flare
        BarState.attach(_barId, screen.name, a0, a0 + cardAlong + flare * 2, "center")
    }
    onCardAlongChanged: _attachBar()
    onCardUChanged: _attachBar()
    onOnBarChanged: _attachBar()

    // Restricts click/hover input to the visible card instead of the whole
    // (mostly-empty, transparent) fixed-size surface. If your Quickshell
    // version doesn't support `mask` on PanelWindow, just delete this block —
    // everything else works without it, you'd just get a slightly larger
    // invisible click-catching area above the card.
    //
    // Both this and the blur region below use explicit window-space geometry
    // instead of `item: card`. A Region with `item` only recomputes when that
    // item's *own* x/y/width/height change — but the slide animation moves
    // `rect` (card's parent), so card's own geometry never changes during
    // open/close. After a close, the region got stuck at the slid-out
    // position (below the surface), and on the next open nothing re-fired it,
    // so the blurred background stayed off-screen = "invisible" panel. Typing
    // a search changed card's height, which is why it only happened when you
    // closed without searching. Binding to rect.x/rect.y fixes that.
    mask: Region {
        x: root._card.x; y: root._card.y
        width: root._card.w; height: root._card.h
    }

    IpcHandler {
        target: "Launcher"
        function toggleAppSearch(): void {
            root.toggle()
        }
        // Dedicated clipboard-history entrypoint — bind this directly to a
        // hotkey (e.g. Super+V) if you want clipboard history to open
        // straight up instead of going through the apps view first.
        function toggleClipboard(): void {
            root.toggle("clipboard")
        }
        // old name (no view of its own): the apps view
        function toggleStartMenu(): void {
            root.toggle("apps")
        }
        function toggleWallpapers(): void {
            root.toggle("wallpapers")
        }
        // the keybind cheatsheet tab (the control center's keyboard button)
        function toggleKeybinds(): void {
            root.toggle("keybinds")
        }
        // saved SSH / RDP / VNC connections
        function toggleConnections(): void {
            root.toggle("connections")
        }
    }

    // Old wallpaper-selector IPC target, kept so existing keybinds still work
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.toggle("wallpapers") }
        function open(): void { if (!root.visible || root.mode !== "wallpapers") root.toggle("wallpapers") }
        function close(): void { if (root.visible) anim.exit() }
    }

    // the same entry points for the rest of the shell: Panels.toggle("clipboard"), …
    readonly property var _panels: ({
        launcher: { toggle: () => root.toggle() },
        clipboard: { toggle: () => root.toggle("clipboard") },
        wallpapers: { toggle: () => root.toggle("wallpapers") },
        keybinds: { toggle: () => root.toggle("keybinds") },
        connections: { toggle: () => root.toggle("connections") }
    })
    // (forEach, not for…of / for…in: qmllint 6.12 skips files with those loops)
    Component.onCompleted: Object.keys(_panels).forEach(n => Panels.register(n, _panels[n]))
    Component.onDestruction: Object.keys(_panels).forEach(n => Panels.unregister(n, _panels[n]))

    // Card + the two inverted corners where it meets the screen edge
    // (each = its square minus a circle), so the corners get blurred too.
    // Whole-pixel card edges for the Regions (they only take ints). Rounding
    // y and height separately while the card's height animates (typing)
    // could leave the region a pixel short of the screen edge, so the
    // lowest pixel row lost its blur; floor the top, ceil the bottom.
    // the card canonically: start along the edge, length along it, depth
    readonly property real cardU: vertical ? card.y : card.x
    readonly property real cardAlong: vertical ? card.height : card.width
    readonly property real cardDepth: vertical ? card.width : card.height
    // canonical rectangle → window rectangle, following the slide (rect), whole pixels
    function _m(u, v, w, d) {
        const g = EdgeMap.mapRect(edge, surfDepth, u, v, w, d)
        const x0 = Math.floor(rect.x + g.x), y0 = Math.floor(rect.y + g.y)
        return { x: x0, y: y0, w: Math.ceil(rect.x + g.x + g.w) - x0, h: Math.ceil(rect.y + g.y + g.h) - y0 }
    }
    readonly property var _card: _m(cardU, 0, cardAlong, cardDepth)
    readonly property var _cardR: EdgeMap.corners(edge, { outerStart: 0, outerEnd: 0, innerEnd: Properties.panelRadius, innerStart: Properties.panelRadius })
    readonly property var _flL: _m(cardU - flare, 0, flare, flare)
    readonly property var _flLc: _m(cardU - flare * 2, 0, flare * 2, flare * 2)
    readonly property var _flR: _m(cardU + cardAlong, 0, flare, flare)
    readonly property var _flRc: _m(cardU + cardAlong, 0, flare * 2, flare * 2)

    BackgroundEffect.blurRegion: Region {
        x: root._card.x; y: root._card.y
        width: root._card.w; height: root._card.h
        topLeftRadius: root._cardR.tl; topRightRadius: root._cardR.tr
        bottomRightRadius: root._cardR.br; bottomLeftRadius: root._cardR.bl

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

    PopupAnimation {
        id: anim
        target: rect
        // slides in from its edge
        direction: ({ bottom: "top", top: "bottom", left: "right", right: "left" })[root.edge]
        // slide by the (collapsed) card, not the whole fixed-height surface:
        // from a surface-height offset the card spent the first half of the
        // slide still below the screen edge, which felt like a slow open
        distance: (root.vertical ? card.width : card.collapsedHeight) + root.flare
        enterDuration: 280
        exitDuration: 180
        onExitFinished: root.visible = false
    }

    // Which sub-view is showing.
    property string mode: "apps" // "apps" | "clipboard" | "connections" | "wallpapers" | "keybinds"
    readonly property var modes: ["apps", "clipboard", "connections", "wallpapers", "keybinds"]

    // Switching modes always clears the search text — carrying an "apps"
    // query like "steam" over into clipboard search would just be
    // confusing. Delete this if you'd rather the query persist across modes.
    onModeChanged: {
        searchField.text = ""
        // Slide the new view in from the side its icon sits on, relative
        // to the previous mode (apps | clipboard | wallpapers, left → right).
        // Skipped while (re)opening, the panel just rises from the bottom then.
        const dir = root.modes.indexOf(root.mode) > root.modes.indexOf(root.prevMode) ? 1 : -1
        root.prevMode = root.mode
        if (root.visible && !card.collapsed) {
            slideAnim.stop()
            slideAnim.view = root.activeView()
            slideAnim.from = dir * root.slideDistance
            slideAnim.start()
        }
    }
    property string prevMode: "apps"
    readonly property int slideDistance: 80

    ParallelAnimation {
        id: slideAnim
        property Item view: null
        property real from: 0
        NumberAnimation { target: slideAnim.view; property: "slideX"; from: slideAnim.from; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: slideAnim.view; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }

    // Reset to the small collapsed state whenever the launcher goes away
    // (Esc, launching an app, …), so the next open always grows up from
    // the bottom instead of starting at the last view's size.
    onVisibleChanged: { _attachBar(); if (!visible) _reset() }
    function _reset() {
        // closing without the exit animation (launching an app) left the panel
        // in place; park it off-screen so the next open slides in cleanly
        anim.hide()
        slideAnim.stop()
        const views = [appSearchView, clipboardView, connectionsView, wallpaperView, keybindsView]
        views.forEach(v => { v.slideX = 0; v.opacity = 1 })
        card.skipHeightAnim = true
        card.collapsed = true
        appSearchView.showAll = false
    }

    // Opens the launcher (optionally straight into a given mode), or closes
    // it if already open. Passing a mode while the launcher is already open
    // just switches views in place instead of closing — that's what makes
    // toggleClipboard() above useful as its own hotkey rather than only a
    // fresh-open action.
    // `scr` (optional): open on that screen, e.g. the bar that was clicked.
    function toggle(targetMode, scr) {
        if (root.visible) {
            if (targetMode && targetMode !== root.mode) {
                root.mode = targetMode
            } else {
                anim.exit()
            }
            return
        }

        if (scr) root.screen = scr
        anim.hide()                 // first open: start off-screen, not at the resting place
        card.skipHeightAnim = true
        root.mode = targetMode || "apps"
        root.visible = true
        searchField.text = ""
        if (root.mode === "clipboard") clipboardView.refresh()

        enterTimer.start()
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: {
            anim.enter()
            searchField.forceActiveFocus()
            card.skipHeightAnim = false
            card.collapsed = false
        }
    }

    // Routes keyboard nav to whichever view is currently visible.
    function activeView() {
        return root.mode === "apps" ? appSearchView
             : root.mode === "clipboard" ? clipboardView
             : root.mode === "keybinds" ? keybindsView
             : root.mode === "connections" ? connectionsView
             : wallpaperView
    }

    // ── Stable wrapper for the open/close slide animation ──
    // Fixed size, fills the whole (fixed-size) surface. PopupAnimation
    // targets THIS, not the dynamically-sized card below.
    //
    // IMPORTANT: this uses explicit width/height, NOT anchors.fill. As soon
    // as PopupAnimation.enter()/exit() assign target.x / target.y directly,
    // any anchor on that axis (anchors.fill, anchors.top, anchors.bottom,
    // etc.) re-asserts itself and silently stomps the assignment back to 0
    // on the next binding evaluation — which is exactly what made the slide
    // never actually appear. width/height alone don't touch x/y, so the
    // item keeps its correct size while staying free to animate position.
    Item {
        id: rect
        width: parent.width
        height: parent.height

        // ── The visible card ──
        // This is the piece that actually grows/shrinks on screen, nested
        // inside the stable `rect` above so its own height animation never
        // interacts with the open/close slide.
        // ── Card outline ──
        // Same shape as the bar popups (components/outline.js), drawn as if it
        // hung from the top and mapped to the launcher's edge (EdgeMap):
        // attached side + inverted corners on the screen edge, rounded corners
        // away from it. Follows the card's animated size.
        Item {
            width: root.surfAlong
            height: root.surfDepth
            transform: Matrix4x4 { matrix: EdgeMap.qmatrix(EdgeMap.matrix(root.edge, root.surfDepth)) }
            Shape {
                id: outline
                x: root.cardU - root.flare      // follows the card (its size animates)
                y: 0
                width: root.cardAlong + root.flare * 2
                height: root.cardDepth
                preferredRendererType: Shape.CurveRenderer

                readonly property string path: Outline.panel(
                    root.flare, root.flare + root.cardAlong, root.cardDepth,
                    root.flare, root.flare, Properties.panelRadius, Properties.panelBorderWidth / 2)

                ShapePath {
                    fillColor: Properties.panelColor
                    strokeColor: "transparent"
                    PathSvg { path: outline.path + "Z" }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Properties.panelBorder
                    strokeWidth: Properties.panelBorderWidth
                    PathSvg { path: outline.path }
                }
            }
        }

        Rectangle {
            id: card
            property bool skipHeightAnim: false
            // collapsed = only search field + mode bar; the "original" state
            // every open starts from
            property bool collapsed: true
            readonly property real collapsedHeight: Properties.buttonHeight + root.modeBarHeight + root.contentSpacing + root.contentMargins
            clip: true
            // on its edge, centred along it; wider in wallpaper mode
            width: root.shownCardWidth
            height: collapsed ? collapsedHeight : content.implicitHeight + root.contentMargins
            // along the edge: its place (inverted corners included), clear of the screen ends
            readonly property int alongPos: EdgeMap.place(PanelGeometry.launcher.along, (root.vertical ? height : width) + root.flare * 2,
                                                          root.vertical ? parent.height : parent.width, Properties.barInset) + root.flare
            x: root.edge === "left" ? 0 : root.edge === "right" ? parent.width - width : alongPos
            y: root.edge === "top" ? 0 : root.edge === "bottom" ? parent.height - height : alongPos
            // sits on the bottom screen edge → only the top corners are rounded
            // drawn by `outline` below (fill + border incl. the inverted corners)
            color: "transparent"

            Behavior on height {
                enabled: !card.skipHeightAnim
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            // switching to / from wallpapers while open: the card widens / narrows
            // (opening straight into a mode starts at its width)
            Behavior on width {
                enabled: !card.skipHeightAnim
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            // one column; the search field and mode bar sit on the edge it
            // comes from: at the bottom, or on top when it comes from the top.
            // Fixed order (a grid with changing rows didn't re-lay out when the
            // edge changed): two slots above the views, two below; the search
            // field and the mode bar are moved into the ones on that edge.
            ColumnLayout {
                id: content
                readonly property bool fromTop: root.edge === "top"
                spacing: root.contentSpacing
                // placed by y, not by switching a top / bottom anchor: while both
                // were set for a moment the anchors stretched it, and that height
                // replaced its own for good (the content then hung out of the card)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                height: implicitHeight
                y: fromTop ? 26 : parent.height - height - 26

                Item {   // mode bar, from the top
                    id: topOuter
                    Layout.fillWidth: true
                    implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
                    visible: children.length > 0
                }
                Item {   // search field, from the top
                    id: topInner
                    Layout.fillWidth: true
                    implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
                    visible: children.length > 0
                }

                // ── The three views, all always instantiated ──
                // Only the active one is visible; the others drop out of the
                // ColumnLayout's height entirely, so `card` animates straight
                // to the new view's height. The incoming view slides in
                // sideways via its `slideX` (see slideAnim).
                AppSearch {
                    id: appSearchView
                    Layout.fillWidth: true
                    maxHeight: root.viewSize("apps").h
                    allAppsHeight: Math.max(root.viewSize("apps").h, root.viewSize("wallpapers").h)
                    query: searchField.text
                    visible: root.mode === "apps"
                    property real slideX: 0
                    transform: Translate { x: appSearchView.slideX }
                    onCloseRequested: { root.visible = false; searchField.text = "" }
                }

                ClipboardHistory {
                    id: clipboardView
                    Layout.fillWidth: true
                    maxHeight: root.viewSize("clipboard").h
                    query: searchField.text
                    active: root.mode === "clipboard"
                    visible: root.mode === "clipboard"
                    property real slideX: 0
                    transform: Translate { x: clipboardView.slideX }
                    onCloseRequested: { root.visible = false; searchField.text = "" }
                }

                ConnectionsView {
                    id: connectionsView
                    Layout.fillWidth: true
                    maxHeight: root.viewSize("connections").h
                    query: searchField.text
                    active: root.mode === "connections"
                    visible: root.mode === "connections"
                    property real slideX: 0
                    transform: Translate { x: connectionsView.slideX }
                    onCloseRequested: anim.exit()
                }

                WallpaperPicker {
                    id: wallpaperView
                    Layout.fillWidth: true
                    maxHeight: root.viewSize("wallpapers").h
                    Layout.preferredHeight: root.viewSize("wallpapers").h
                    Layout.maximumHeight: root.viewSize("wallpapers").h
                    query: searchField.text
                    active: root.mode === "wallpapers"
                    visible: root.mode === "wallpapers"
                    property real slideX: 0
                    transform: Translate { x: wallpaperView.slideX }
                    onCloseRequested: anim.exit()
                }

                KeybindsView {
                    id: keybindsView
                    Layout.fillWidth: true
                    maxHeight: root.viewSize("keybinds").h
                    Layout.preferredHeight: root.viewSize("keybinds").h
                    Layout.maximumHeight: root.viewSize("keybinds").h
                    query: searchField.text
                    active: root.mode === "keybinds"
                    visible: root.mode === "keybinds"
                    property real slideX: 0
                    transform: Translate { x: keybindsView.slideX }
                    onCloseRequested: anim.exit()
                }

                Item {   // search field, from the bottom
                    id: bottomInner
                    Layout.fillWidth: true
                    implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
                    visible: children.length > 0
                }
                Item {   // mode bar, from the bottom
                    id: bottomOuter
                    Layout.fillWidth: true
                    implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
                    visible: children.length > 0
                }

                SearchField {
                    id: searchField
                    parent: content.fromTop ? topInner : bottomInner
                    width: parent ? parent.width : 0
                    height: Properties.buttonHeight
                    implicitHeight: Properties.buttonHeight
                    icon: root.mode === "apps" ? "󰍉" : root.mode === "clipboard" ? "󰅍" : root.mode === "keybinds" ? "󰌌"
                        : root.mode === "connections" ? "󰢹" : "󰸉"
                    placeholderText: root.mode === "apps" ? "Search apps"
                                   : root.mode === "clipboard" ? "Search clipboard history"
                                   : root.mode === "keybinds" ? "Search keybinds"
                                   : root.mode === "connections" ? "Search connections (SSH, RDP, VNC)"
                                   : "Search wallpapers"

                    Keys.onDownPressed: root.activeView().moveDown()
                    Keys.onUpPressed: root.activeView().moveUp()
                    Keys.onReturnPressed: root.activeView().activateCurrent()

                    // Tab cycles apps -> clipboard -> wallpapers -> keybinds without
                    // touching the mouse. Remove if you'd rather Tab do the
                    // usual focus-chain thing.
                    Keys.onTabPressed: (event) => {
                        root.mode = root.modes[(root.modes.indexOf(root.mode) + 1) % root.modes.length]
                        event.accepted = true
                    }

                    // Esc always closes. Delete only closes when the field is
                    // already empty, so it doesn't fight with deleting
                    // characters while typing.
                    Keys.onEscapePressed: anim.exit()
                    Keys.onDeletePressed: (event) => {
                        if (searchField.text.length === 0) {
                            anim.exit()
                        } else {
                            event.accepted = false
                        }
                    }
                }

                // ── Mode switcher + wallpaper tools ──
                RowLayout {
                    id: modeBar
                    parent: content.fromTop ? topOuter : bottomOuter
                    width: parent ? parent.width : 0
                    height: root.modeBarHeight
                    implicitHeight: root.modeBarHeight
                    spacing: 8

                    Repeater {
                        model: [
                            { value: "apps",       glyph: Icons.get("modeApps"), tip: "Apps" },
                            { value: "clipboard",  glyph: Icons.get("modeClipboard"), tip: "Clipboard history" },
                            { value: "connections", glyph: Icons.get("modeConnections"), tip: "Connections" },
                            { value: "wallpapers", glyph: Icons.get("modeWallpapers"), tip: "Wallpapers" },
                            { value: "keybinds",   glyph: Icons.get("modeKeybinds"), tip: "Keybinds" }
                        ]

                        IconButton {
                            required property var modelData
                            icon: modelData.glyph
                            tooltip: modelData.tip
                            active: root.mode === modelData.value
                            onClicked: root.mode = modelData.value
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Keybinds: re-read the compositor config
                    IconButton {
                        visible: root.mode === "keybinds"
                        icon: "󰑐"
                        tooltip: "Reload from " + (Compositor.name || "niri") + " config"
                        onClicked: Keybinds.refresh()
                    }

                    // Connections: check again / edit them
                    IconButton {
                        visible: root.mode === "connections"
                        icon: "󰑐"
                        tooltip: "Check which are reachable"
                        onClicked: RemoteConnections.probe()
                    }
                    IconButton {
                        visible: root.mode === "connections"
                        icon: "󰒓"
                        tooltip: "Edit connections"
                        onClicked: { Panels.call("settings", "openPage", "connections"); anim.exit() }
                    }

                    // Wallpaper tools, only in wallpaper mode
                    IconButton {
                        visible: root.mode === "wallpapers"
                        icon: "󰡍"
                        tooltip: "Expand / collapse all folders"
                        onClicked: wallpaperView.toggleExpandAll()
                    }
                    IconButton {
                        visible: root.mode === "wallpapers"
                        icon: "󰉋"
                        tooltip: "Open wallpapers folder"
                        onClicked: wallpaperView.openFolder()
                    }
                    IconButton {
                        visible: root.mode === "wallpapers"
                        icon: "󰑐"
                        tooltip: "Rescan wallpapers"
                        onClicked: wallpaperView.rescan()
                    }
                    IconButton {
                        visible: root.mode === "wallpapers"
                        icon: "󰓛"
                        tooltip: "Stop the running wallpaper command"
                        interactive: wallpaperView.applying
                        textColor: wallpaperView.applying ? Colors.red : Properties.color
                        onClicked: wallpaperView.stop()
                    }
                }
            }
        }
    }
}
