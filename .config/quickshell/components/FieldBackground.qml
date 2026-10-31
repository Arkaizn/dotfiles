import QtQuick
import qs.services

// The well of every text input (single-line SearchField, multi-line notes,
// signatures, templates): darker fill, soft card border that brightens on
// focus, a thin line growing from the centre while focused, red on error.
//   TextArea { id: notes; background: FieldBackground { focused: notes.activeFocus } }
//   FieldBackground { focused: area.activeFocus; TextArea { id: area; background: null … } }
Rectangle {
    id: bg
    property bool focused: false
    property bool hovered: false
    property bool error: false

    radius: Tokens.radius.lg
    // focus only nudges things: fill a touch lighter, border a touch brighter
    color: Colors.light ? (focused ? Colors.neutral(1, 0.9) : Colors.neutral(1, 0.65))
                        : (focused ? Colors.shade(0.23) : Colors.shade(0.27))
    border.width: Properties.panelBorderWidth
    border.color: error ? Colors.danger
                : focused ? Colors.fade(0.16)
                : hovered ? Colors.fade(0.13)
                : Properties.cardBorder
    Behavior on color { ColorAnimation { duration: Anim.normal } }
    Behavior on border.color { ColorAnimation { duration: Anim.normal } }

    // thin highlight that grows from the centre when focused
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.space.s1
        anchors.horizontalCenter: parent.horizontalCenter
        height: 1.5
        radius: 1
        width: bg.focused ? parent.width - parent.radius * 2 : 0
        color: bg.error ? Colors.danger : Colors.fade(0.14)
        Behavior on width { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    }
}
