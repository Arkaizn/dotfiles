pragma Singleton
import QtQuick

QtObject {
    // ── Master speed scale — 1.0 = normal, 0.5 = twice as fast ──
    readonly property real scale: 1.0

    // ── Durations (ms) ───────────────────────────────────────────
    readonly property int popupIn:   Math.round(220 * scale)
    readonly property int popupOut:  Math.round(180 * scale)
    readonly property int hover:     Math.round(100 * scale)
    readonly property int color:     Math.round(120 * scale)

    // ── Easing curves ────────────────────────────────────────────
    readonly property int easingIn:  Easing.OutCubic
    readonly property int easingOut: Easing.InCubic
    readonly property int easingBounce: Easing.OutBack
}