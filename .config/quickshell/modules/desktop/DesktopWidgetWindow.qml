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
