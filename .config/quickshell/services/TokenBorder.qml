import QtQuick
import qs.services

// Tokens.border.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property real hair: 0.5
    readonly property real thin: 1
    readonly property real panel: Properties.panelBorderWidth   // bar, popups, cards
    readonly property real control: 1.5                        // buttons, toggles, fields
    readonly property real selected: 2                          // the picked item
    readonly property real focus: 2                             // keyboard focus ring
}
