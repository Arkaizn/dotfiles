import QtQuick
import qs.services

// Tokens.alpha.* — a type of its own (not an inline QtObject) so qmllint
// knows its members. See Tokens.qml / DESIGN.md.
QtObject {
    readonly property real disabled: 0.4
    readonly property real dragged: 0.35
}
