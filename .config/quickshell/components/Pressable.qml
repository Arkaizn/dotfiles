import QtQuick
import qs.services

// Base of every clickable control (buttons, toggles, chips, rows): the same
// hover, press, keyboard and accessibility behaviour everywhere.
//
//   Pressable {
//       accessibleName: "Delete"      // what a screen reader says (defaults to tooltip)
//       tooltip: "Delete"             // styled tooltip after Anim.tooltipDelay
//       interactive: true             // false = disabled: no hover / clicks, Tokens.alpha.disabled
//       busy: false                   // working: no clicks, not dimmed (controls show a Spinner)
//       onClicked: …
//   }
//
// - Mouse: hover + press state (`hovered`, `pressed`), pointing-hand cursor.
// - Keyboard: reachable with Tab; Space / Enter press it (pressed shows while
//   the key is down, clicked on release, like a mouse click). A focus ring
//   shows only while it has keyboard focus — a mouse click never focuses it.
// - Disabled: `interactive: false` (not `enabled`, so tooltips of disabled
//   controls still explain why). dimDisabled: false for static indicators
//   that shouldn't look disabled.
// Derived controls put their look as children; the MouseArea sits below them
// and gets every click their Texts / Rectangles don't take.
Item {
    id: root

    property bool interactive: true
    property bool busy: false
    property string tooltip: ""
    property string accessibleName: tooltip
    property int accessibleRole: Accessible.Button
    property bool dimDisabled: true
    property bool showFocusRing: true
    property real focusRadius: Tokens.radius.md
    property alias cursorShape: mouse.cursorShape
    property alias acceptedButtons: mouse.acceptedButtons
    readonly property bool hovered: mouse.containsMouse && interactive && !busy
    readonly property bool pressed: (mouse.pressed || keyDown) && interactive && !busy
    property bool keyDown: false

    signal clicked()
    signal rightClicked()

    activeFocusOnTab: interactive
    opacity: interactive || !dimDisabled ? 1 : Tokens.alpha.disabled
    Behavior on opacity { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }

    Accessible.role: accessibleRole
    Accessible.name: accessibleName
    Accessible.focusable: interactive
    Accessible.onPressAction: if (interactive && !busy) clicked()

    function isPressKey(k) { return k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter }
    Keys.onPressed: e => {
        if (interactive && !busy && isPressKey(e.key) && !e.isAutoRepeat) { keyDown = true; e.accepted = true }
    }
    Keys.onReleased: e => {
        if (keyDown && isPressKey(e.key) && !e.isAutoRepeat) { keyDown = false; e.accepted = true; clicked() }
    }
    onActiveFocusChanged: if (!activeFocus) keyDown = false

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive && !root.busy
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => m.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }

    // ring and tooltip exist only while needed: there are hundreds of
    // controls, and a Popup + a Rectangle each would cost startup time and memory
    Loader {
        anchors.fill: parent
        z: 100
        active: root.showFocusRing && root.activeFocus
        sourceComponent: FocusRing { controlRadius: root.focusRadius; shown: true }
    }
    Loader {
        // the tip positions itself against this, so it must cover the control
        anchors.fill: parent
        active: root.hovered && root.tooltip !== ""
        sourceComponent: HoverTip { text: root.tooltip; shown: true }
    }
}
