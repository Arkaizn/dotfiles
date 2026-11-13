import QtQuick
import qs.services

// Tokens.radius.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property int xs: 2                          // progress tracks, scrollbar thumbs
    readonly property int sm: 4                          // event chips, tags, small marks
    readonly property int md: Properties.radius          // 8 — chips, small tiles
    readonly property int lg: Properties.radius + 2      // 10 — buttons, fields
    readonly property int xl: Properties.radius + 4      // 12 — menus, popovers, big tiles
    readonly property int card: Properties.radius + 6    // 14 — inner cards
    readonly property int dialog: Properties.radius + 10 // 18 — modal cards
    readonly property int popup: Properties.popupRadius  // 12 — notification popups
    readonly property int panel: Properties.panelRadius  // 30 — dashboard, launcher, …
    readonly property int bar: Properties.barRadius      // 15 — the bar

    // A surface inside another surface: inner radius = outer radius − the
    // padding between them, so the corners stay concentric (DESIGN.md → Craft
    // rules). Never below sm; when the padding is larger than the outer radius
    // the inner surface takes its normal token instead.
    function inner(outer: real, pad: real): real { return Math.max(sm, outer - pad) }
}
