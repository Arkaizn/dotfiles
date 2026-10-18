import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
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

    // NOTE: only "bottom" is anchored (no left/right), which is what centers
    // this horizontally in Quickshell — same trick the dashboard uses.
    anchors {
        bottom: true
    }
    // card width (apps / clipboard; the wallpaper grid gets a wider card),
    // surface = the widest card + room for the inverted corners on both sides.
    // The surface keeps that width all the time (see the height note below);
    // only the visible card animates between the two widths.
    readonly property int cardWidth: 640
    readonly property int wallpaperCardWidth: 960
    readonly property int shownCardWidth: mode === "wallpapers" || mode === "keybinds" ? wallpaperCardWidth : cardWidth
    readonly property int flare: Properties.flareRadius
    implicitWidth: Math.max(cardWidth, wallpaperCardWidth) + flare * 2

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
    readonly property int maxResultsHeight: 360
    readonly property int wallpaperMaxHeight: 520 // the wallpaper grid gets more room
    readonly property int contentSpacing: 8
    readonly property int modeBarHeight: Properties.buttonHeight
    readonly property int contentMargins: 16 + 26 // matches content's anchors.margins + bottomMargin below

    // tallest results list + search bar + mode-switcher row + the two gaps
    // between them (content always has exactly 3 visible children: one of
    // the two views, the search field, and the mode bar) + outer margins.
    implicitHeight: Math.max(maxResultsHeight, wallpaperMaxHeight) + contentSpacing * 2 + Properties.buttonHeight + modeBarHeight + contentMargins

    color: '#00000000'
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

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
        x: rect.x + card.x
        y: root.cardTop
        width: card.width
        height: root.cardBottom - root.cardTop
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
        function toggleStartMenu(): void {
            root.toggle("startMenu")
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

    // Card + the two inverted corners where it meets the screen edge
    // (each = its square minus a circle), so the corners get blurred too.
    // Whole-pixel card edges for the Regions (they only take ints). Rounding
    // y and height separately while the card's height animates (typing)
    // could leave the region a pixel short of the screen edge, so the
    // lowest pixel row lost its blur; floor the top, ceil the bottom.
    readonly property int cardTop: Math.floor(rect.y + card.y)
    readonly property int cardBottom: Math.ceil(rect.y + card.y + card.height)

    BackgroundEffect.blurRegion: Region {
        x: rect.x + card.x
        y: root.cardTop
        width: card.width
        height: root.cardBottom - root.cardTop
        topLeftRadius: Properties.panelRadius
        topRightRadius: Properties.panelRadius

        Region {
            x: rect.x + card.x - root.flare; y: root.cardBottom - root.flare
            width: root.flare; height: root.flare
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: rect.x + card.x - root.flare * 2; y: root.cardBottom - root.flare * 2
                width: root.flare * 2; height: root.flare * 2
            }
        }
        Region {
            x: rect.x + card.x + card.width; y: root.cardBottom - root.flare
            width: root.flare; height: root.flare
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: rect.x + card.x + card.width; y: root.cardBottom - root.flare * 2
                width: root.flare * 2; height: root.flare * 2
            }
        }
    }

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
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
    onVisibleChanged: if (!visible) {
        slideAnim.stop()
        for (const v of [appSearchView, clipboardView, connectionsView, wallpaperView, keybindsView]) { v.slideX = 0; v.opacity = 1 }
        card.skipHeightAnim = true
        card.collapsed = true
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
        // Same shape as the bar popups (components/outline.js), flipped
        // vertically: attached edge + inverted corners at the bottom screen
        // edge, rounded corners at the top. Follows card's animated height.
        Shape {
            id: outline
            x: card.x - root.flare          // follows the card (its width animates)
            y: card.y
            width: card.width + root.flare * 2
            height: card.height
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.y: outline.height / 2; yScale: -1 }

            readonly property string path: Outline.panel(
                root.flare, root.flare + card.width, card.height,
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

        Rectangle {
            id: card
            property bool skipHeightAnim: false
            // collapsed = only search field + mode bar; the "original" state
            // every open starts from
            property bool collapsed: true
            readonly property real collapsedHeight: Properties.buttonHeight + root.modeBarHeight + root.contentSpacing + root.contentMargins
            clip: true
            // centered; wider in wallpaper mode
            anchors.bottom: parent.bottom
            width: root.shownCardWidth
            x: Math.round((parent.width - width) / 2)
            height: collapsed ? collapsedHeight : content.implicitHeight + root.contentMargins
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

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                anchors.bottomMargin: 26
                spacing: root.contentSpacing

                // ── The three views, all always instantiated ──
                // Only the active one is visible; the others drop out of the
                // ColumnLayout's height entirely, so `card` animates straight
                // to the new view's height. The incoming view slides in
                // sideways via its `slideX` (see slideAnim).
                AppSearch {
                    id: appSearchView
                    Layout.fillWidth: true
                    maxHeight: root.maxResultsHeight
                    query: searchField.text
                    visible: root.mode === "apps"
                    property real slideX: 0
                    transform: Translate { x: appSearchView.slideX }
                    onCloseRequested: { root.visible = false; searchField.text = "" }
                }

                ClipboardHistory {
                    id: clipboardView
                    Layout.fillWidth: true
                    maxHeight: root.maxResultsHeight
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
                    maxHeight: root.maxResultsHeight
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
                    maxHeight: root.wallpaperMaxHeight
                    Layout.preferredHeight: root.wallpaperMaxHeight
                    Layout.maximumHeight: root.wallpaperMaxHeight
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
                    maxHeight: root.wallpaperMaxHeight
                    Layout.preferredHeight: root.wallpaperMaxHeight
                    Layout.maximumHeight: root.wallpaperMaxHeight
                    query: searchField.text
                    active: root.mode === "keybinds"
                    visible: root.mode === "keybinds"
                    property real slideX: 0
                    transform: Translate { x: keybindsView.slideX }
                    onCloseRequested: anim.exit()
                }

                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Properties.buttonHeight
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
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.modeBarHeight
                    spacing: 8

                    Repeater {
                        model: [
                            { value: "apps",       glyph: "󰀻", tip: "Apps" },
                            { value: "clipboard",  glyph: "󰅍", tip: "Clipboard history" },
                            { value: "connections", glyph: "󰢹", tip: "Connections" },
                            { value: "wallpapers", glyph: "󰸉", tip: "Wallpapers" },
                            { value: "keybinds",   glyph: "󰌌", tip: "Keybinds" }
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
                        onClicked: { Quickshell.execDetached(["qs", "ipc", "call", "settings", "openPage", "connections"]); anim.exit() }
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
                        textColor: wallpaperView.applying ? "#f38ba8" : Properties.color
                        onClicked: wallpaperView.stop()
                    }
                }
            }
        }
    }
}
