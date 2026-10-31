import QtQuick
import qs.services

// Tokens.icon.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property int xs: 11
    readonly property int sm: 12
    readonly property int md: 14                  // glyph in a button
    readonly property int lg: Properties.iconSize // 18 — bar icons
    readonly property int xl: 24
    readonly property int app: 36                 // app icons in lists
    readonly property int appLarge: 48            // app icons in grids, notifications
    readonly property int art: 80                 // album art, avatars in cards
}
