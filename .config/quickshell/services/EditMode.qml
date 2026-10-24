pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Live layout editing ("jiggle mode"): the bar, the dashboard or the control
// center shows its parts wiggling; drag them around, − takes one away.
// Changes go straight to BarLayout / PanelLayout (settings.json), so the
// settings app shows them too and its Reset buttons bring the defaults back.
//
// "panels" = the panel editor (modules/paneleditor: the bar's edge, panel
// sizes and places), on one monitor.
//
// Start: long-press an empty spot of the bar / dashboard / control center,
// the "Edit live" buttons in the settings app, or
//   qs ipc call edit bar | dashboard | controlCenter | controlCenterButtons | panels | stop
Singleton {
    id: root

    // "" | "bar" | "dashboard" | "controlCenter" (its cards) | "controlCenterButtons" (the buttons in them) | "panels"
    property string target: ""
    property string screen: ""        // bar: the monitor being edited
    property bool dragging: false     // something is being dragged (drop zones show)
    readonly property bool active: target !== ""
    readonly property bool controlCenter: target === "controlCenter" || target === "controlCenterButtons"

    function start(what, screenName) {
        if ((what === "bar" || what === "panels") && !screenName && (Compositor.isNiri || Compositor.isHyprland)) {
            Compositor.focusedOutput(name => root.start(what, name || (Quickshell.screens[0]?.name ?? "")))
            return
        }
        dragging = false
        screen = screenName || (Quickshell.screens[0]?.name ?? "")
        target = what
    }
    function stop() { dragging = false; target = "" }
    function toggle(what, screenName) { target === what ? stop() : start(what, screenName) }

    // ── Wiggle ──────────────────────────────────────────────────────────────
    // One shared clock; each part is offset by a seed so they don't all move in step.
    property real phase: 0
    NumberAnimation {
        target: root; property: "phase"
        from: 0; to: 1; duration: 280
        loops: Animation.Infinite
        running: root.active
        onStopped: root.phase = 0
    }
    // rotation in degrees for a part; 0 while not editing
    function wiggle(seed, amp) { return active ? Math.sin((phase + seed) * 2 * Math.PI) * amp : 0 }
    // stable 0..1 offset from an id
    function seed(id) {
        let h = 0
        for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 997
        return h / 997
    }

    IpcHandler {
        target: "edit"
        function bar(): void { root.start("bar") }
        function dashboard(): void { root.start("dashboard") }
        function controlCenter(): void { root.start("controlCenter") }
        function controlCenterButtons(): void { root.start("controlCenterButtons") }
        function panels(): void { root.start("panels") }
        function stop(): void { root.stop() }
        function get(): string { return root.target || "off" }
    }
}
