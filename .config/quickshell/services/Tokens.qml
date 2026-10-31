pragma Singleton
import Quickshell
import QtQuick
import qs.services

// Design tokens: the one place for type sizes, spacing, corner radii, icon
// sizes, borders and state opacities. Colours are in Colors.qml, motion in
// Anim.qml. DESIGN.md says which token to take when.
//
//   Text { font.pixelSize: Tokens.font.caption }
//   Rectangle { radius: Tokens.radius.card }
//   ColumnLayout { spacing: Tokens.space.md }
//
// Properties.qml stays the surface of the user's settings (settings.json keys
// must keep working); the scales below derive from it, so "Font size" scales
// every text and "Buttons & fields" corners move every control with it.
// Modules use these names, never the numbers: a literal in a module is either
// a documented exception (DESIGN.md → Exceptions) or a bug.
//
// Copied into the greeter build (greeter/manifest.txt): keep the imports to
// services the greeter has (Properties, Settings, Colors).
Singleton {
    id: root

    // ── Type scale ───────────────────────────────────────────────────────────
    // Steps relative to the user's base size (Properties.pixelSize, 13), so the
    // setting reaches every text; at the default each step is the size most
    // of the shell already used for that role.
    readonly property TokenFont font: TokenFont {}

    // ── Spacing ──────────────────────────────────────────────────────────────
    // A 4 px scale with the 2 px half steps the layout is built on (6, 10, 14
    // are real, frequent steps; snapping them to 4 / 8 / 12 / 16 would loosen
    // or tighten every page). Named by their size so a value off the grid
    // can't hide behind a name. Negative margins that widen a hit area stay
    // literal.
    readonly property TokenSpace space: TokenSpace {}

    // ── Corner radii ─────────────────────────────────────────────────────────
    // md follows "Buttons & fields" (Properties.radius), panel follows "Big
    // panels" (Properties.panelRadius): the user's corner settings drive the
    // scale. A pill is height / 2 (write it as such); window corners match
    // niri's (Compositor.appRadius).
    readonly property TokenRadius radius: TokenRadius {}

    // ── Icons (Nerd Font glyph sizes and image sizes) ────────────────────────
    readonly property TokenIcon icon: TokenIcon {}

    // ── Borders ──────────────────────────────────────────────────────────────
    readonly property TokenBorder border: TokenBorder {}

    // ── State opacities (not "state": that name is taken on every Item) ─────
    readonly property TokenAlpha alpha: TokenAlpha {}

    // ── Control sizes ────────────────────────────────────────────────────────
    readonly property TokenSize size: TokenSize {}
}
