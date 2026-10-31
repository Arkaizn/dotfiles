import QtQuick
import qs.services

// Tokens.space.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property int s1: 1
    readonly property int s2: 2
    readonly property int s4: 4
    readonly property int s6: 6
    readonly property int s8: 8
    readonly property int s10: 10
    readonly property int s12: 12
    readonly property int s14: 14
    readonly property int s16: 16
    readonly property int s20: 20
    readonly property int s24: 24
    readonly property int s32: 32
    // semantic aliases
    readonly property int cardPad: 14     // padding inside a card (settings, calendar, mail)
    readonly property int rowPadH: 16     // horizontal padding of a list / setting row
    readonly property int rowPadV: 10     // vertical padding of a list / setting row
    readonly property int gap: 6          // between an icon and its label
    readonly property int stack: 8        // between stacked controls
}
