import QtQuick
import qs.services

// Tokens.size.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property int control: Properties.buttonHeight   // 32 — buttons, fields
    readonly property int controlSmall: 26
    readonly property int controlLarge: 40
    readonly property int row: 44                            // one list / setting row
}
