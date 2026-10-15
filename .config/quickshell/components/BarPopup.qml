import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import "outline.js" as Outline

// ── A popup that hangs under the bar ──
// Shared by the notification center, dashboard and wallpaper selector.
//
//   BarPopup {
//       side: "right"              // flush with the bar's right end
//       panelWidth: 400
//       panelHeight: col.implicitHeight + padding * 2
//       ipcName: "notifCenter"     // → qs ipc call notifCenter toggle
//       ColumnLayout { id: col; anchors { left: parent.left; right: parent.right } ... }
//   }
//
// Shape: one outline drawn as a Shape — inverted ("flare") corners where it
// meets the bar, rounded bottom corners, and the shared panel border on
// every edge except the one it shares with the bar (the bar leaves a gap
// in its own border there, see BarState / Bar.qml).
//
// Open/close: the panel unrolls downward from the bar (its height animates),
// the content slides down a little and fades in. The layer surface itself
// never resizes — only items inside it — so it stays smooth.
PanelWindow {
    id: root

    // ── Config ────────────────────────────────────────────────
    property string side: "right"      // "left" | "right" | "center"
    property int panelWidth: 400
    property real panelHeight: 300     // fully open height, including padding
    property int maxHeight: Math.ceil(panelHeight) // surface height; set ≥ panelHeight if content grows
    property int padding: 10
    property bool autoClose: true      // close shortly after the pointer leaves
    property string ipcName: ""

    default property alias content: body.data

    // ── State ─────────────────────────────────────────────────
    property bool shown: false         // logical state; `visible` lags during the close animation
    property real reveal: 0            // 0 = closed, 1 = fully open
    property bool hasBeenHovered: false

    signal opening()
    signal popupClosed()

    readonly property int flareL: side === "left" ? 0 : Properties.flareRadius
    readonly property int flareR: side === "right" ? 0 : Properties.flareRadius

    // Current geometry — corners shrink with the panel so it never folds over itself
    readonly property real h: panelHeight * reveal
    readonly property real r: Math.min(Properties.panelRadius, h / 2)
    readonly property real fl: Math.min(flareL, Math.max(0, h - r))
    readonly property real fr: Math.min(flareR, Math.max(0, h - r))

    visible: false
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true; left: side === "left"; right: side === "right" }
    margins {
        left: side === "left" ? Properties.barInset : 0
        right: side === "right" ? Properties.barInset : 0
    }
    implicitWidth: panelWidth + flareL + flareR
    implicitHeight: maxHeight

    // ── API ───────────────────────────────────────────────────
    // `scr`: the screen whose bar was clicked (optional) — opens there.
    function toggle(scr) {
        if (shown && (!scr || scr === screen)) close()
        else open(scr)
    }

    function open(scr) {
        // No screen given (keybind / IPC): open on the focused output.
        if (!scr && !shown && Quickshell.env("NIRI_SOCKET")) {
            focusedOutputProc.running = true
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

    // ── Internals ─────────────────────────────────────────────
    readonly property string _id: "barpopup:" + (ipcName || String(root))

    function _attach() {
        const s = screen
        if (!s) return
        const w = implicitWidth
        const x0 = side === "left" ? Properties.barInset
                 : side === "right" ? s.width - Properties.barInset - w
                 : Math.floor((s.width - w) / 2)
        BarState.attach(_id, s.name, x0, x0 + w, side)
    }

    onImplicitWidthChanged: if (shown) _attach()

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

    Process {
        id: focusedOutputProc
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = ""
                try { name = JSON.parse(text).name } catch (e) {}
                const scr = Quickshell.screens.find(s => s.name === name)
                root.open(scr ?? root.screen ?? Quickshell.screens[0])
            }
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

    // ── Regions ───────────────────────────────────────────────
    mask: Region { item: frame }

    // Body (rounded bottom) + each flare = its square minus a circle,
    // so the inverted corners are blurred too.
    BackgroundEffect.blurRegion: Region {
        x: root.flareL; y: 0
        width: root.panelWidth; height: Math.ceil(root.h)
        bottomLeftRadius: root.r; bottomRightRadius: root.r

        Region {
            x: root.flareL - root.fl; y: 0
            width: root.fl; height: root.fl
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: root.flareL - root.fl * 2; y: 0
                width: root.fl * 2; height: root.fl * 2
            }
        }
        Region {
            x: root.flareL + root.panelWidth; y: 0
            width: root.fr; height: root.fr
            Region {
                shape: RegionShape.Ellipse; intersection: Intersection.Subtract
                x: root.flareL + root.panelWidth; y: 0
                width: root.fr * 2; height: root.fr * 2
            }
        }
    }

    // ── Visuals ───────────────────────────────────────────────
    Item {
        id: frame
        width: root.width
        height: Math.ceil(root.h)
        clip: true

        HoverHandler {
            enabled: root.autoClose
            onHoveredChanged: {
                if (hovered) {
                    root.hasBeenHovered = true
                    autoCloseTimer.stop()
                } else if (root.hasBeenHovered && root.shown) {
                    autoCloseTimer.start()
                }
            }
        }

        Shape {
            id: shape
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            readonly property string outline: Outline.panel(
                root.flareL, root.flareL + root.panelWidth, root.h,
                root.fl, root.fr, root.r, Properties.panelBorderWidth / 2)

            ShapePath {
                fillColor: Properties.panelColor
                strokeColor: "transparent"
                PathSvg { path: shape.outline + "Z" }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Properties.panelBorder
                strokeWidth: Properties.panelBorderWidth
                PathSvg { path: shape.outline }
            }
        }

        // Content: slides down a bit and fades in as the panel unrolls
        Item {
            id: body
            x: root.flareL + root.padding
            y: root.padding - (1 - root.reveal) * 24
            width: root.panelWidth - root.padding * 2
            height: root.panelHeight - root.padding * 2
            opacity: Math.min(1, root.reveal * 1.5)
        }
    }
}
