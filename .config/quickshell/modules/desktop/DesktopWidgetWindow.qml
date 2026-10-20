import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.lib

// One widget on one monitor: its own small layer surface in the "bottom"
// layer - above the wallpaper, below every window. So a window over it always
// gets the clicks, and the rest of the desktop stays free (no full-screen
// surface catching clicks). Long-press opens the live editor.
PanelWindow {
    id: win
    required property string instId
    readonly property var inst: DesktopWidgets.byId[instId] ?? null

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:desktop-widget"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true }
    color: "transparent"
    visible: inst !== null && !DesktopWidgets.editing && frame.shown

    readonly property real s: inst?.scale ?? 1
    readonly property var box: DeskWidgets.bounds(frame.implicitWidth * s, frame.implicitHeight * s, inst?.rot ?? 0)
    implicitWidth: Math.max(1, box.w)
    implicitHeight: Math.max(1, box.h)
    // centre at x / y of the screen, kept on it
    margins.left: Math.round(DeskWidgets.clamp((inst?.x ?? 0.5) * screen.width - box.w / 2, 0, Math.max(0, screen.width - box.w)))
    margins.top: Math.round(DeskWidgets.clamp((inst?.y ?? 0.5) * screen.height - box.h / 2, 0, Math.max(0, screen.height - box.h)))

    // card / glass backgrounds blur what's behind them, like the bar. Not when
    // turned: a blur region can't rotate, it would stick out past the corners
    readonly property bool blurred: frame.bg !== "none" && Math.abs(inst?.rot ?? 0) < 0.5
    BackgroundEffect.blurRegion: Region {
        x: Math.round((win.width - frame.width * win.s) / 2)
        y: Math.round((win.height - frame.height * win.s) / 2)
        width: win.blurred ? Math.round(frame.width * win.s) : 0
        height: win.blurred ? Math.round(frame.height * win.s) : 0
        radius: 22 * win.s
    }

    MouseArea {
        anchors.fill: parent
        pressAndHoldInterval: 600
        onPressAndHold: DesktopWidgets.startEdit(win.screen.name, win.instId)
    }

    WidgetFrame {
        id: frame
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        scale: win.s
        rotation: win.inst?.rot ?? 0
        inst: win.inst
        active: win.visible
    }
}
