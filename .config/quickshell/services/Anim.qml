pragma Singleton
import QtQuick
import qs.services

// Motion tokens: durations and easing curves for every animation in the
// shell. DESIGN.md → Motion says which one to take when.
//
//   Behavior on color { ColorAnimation { duration: Anim.fast } }
//   NumberAnimation { duration: Anim.medium; easing.type: Anim.standard }
//   SequentialAnimation { loops: Animation.Infinite; running: Anim.ambient && … }
//
// Settings → Motion: "Animation length" stretches every duration (scale) and
// "Reduce motion" makes them instant. Looping / ambient animations (pulses,
// marquees, breathing) must also check `ambient`: with every duration at 0 a
// loop would spin, and reduced motion means they shouldn't move at all.
QtObject {
    // ── Master speed ─────────────────────────────────────────────────────────
    // 1.0 = normal, 0.5 = twice as fast, 0 = instant (reduce motion)
    readonly property real scale: Properties.reduceMotion ? 0 : Math.max(0.25, Properties.animSpeed)
    readonly property bool ambient: !Properties.reduceMotion

    function ms(base) { return Math.round(base * scale) }

    // ── Durations (ms) ───────────────────────────────────────────────────────
    readonly property int instant: ms(80)      // press feedback, tiny fades
    readonly property int fast: ms(120)        // hover colour / scale
    readonly property int normal: ms(180)      // show / hide, toggles, small moves
    readonly property int medium: ms(240)      // popups and pages in, height changes
    readonly property int slow: ms(340)        // drawers, page slides, expands
    readonly property int slower: ms(500)      // lockscreen stage, wizard steps
    readonly property int theme: ms(600)       // pywal crossfade, album art
    // panels hanging from the bar (dashboard, control center, launcher, …):
    // all open and close with the same pair
    readonly property int panelIn: ms(290)
    readonly property int panelOut: ms(190)
    // buttons follow the user's "Animation length (ms)" (Settings → Motion → Buttons)
    readonly property int button: ms(Properties.bDuration)

    // hover time before a tooltip shows (not scaled: it's a wait, not a motion)
    readonly property int tooltipDelay: 450

    // ── Easing curves ────────────────────────────────────────────────────────
    readonly property int standard: Easing.OutCubic     // the default: things arriving / settling
    readonly property int exit: Easing.InCubic          // things leaving
    readonly property int emphasized: Easing.OutQuint   // big moves: pages, drawers, panels
    readonly property int pop: Easing.OutBack           // pop-ins with a little overshoot
    readonly property int loop: Easing.InOutSine        // pulses, marquees, breathing
}
