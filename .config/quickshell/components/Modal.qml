import QtQuick
import qs.services

// Dimmed overlay with a card in the middle; click outside or Esc closes it,
// Enter presses its primary button (the one visible, enabled ActionButton
// with variant "primary", if there is exactly one) — when the focus is on a
// control (after Tab). In a text field the field decides, as before: single
// line fields that should submit say so with onAccepted, multi-line ones
// take Enter as a new line.
//   Modal { id: m; cardWidth: 460; …content… }   m.open() / m.close()
//   enterAccepts: false   where Enter must never trigger it (the composer: Send)
Item {
    id: root

    property bool shown: false
    property int cardWidth: 460
    // unsaved input: clicks outside / Esc shake the card instead of closing it
    property bool keepOpen: false
    property bool enterAccepts: true
    default property alias content: inner.data
    signal closed()

    function open() { shown = true; card.forceActiveFocus() }
    function close() { if (shown) { shown = false; closed() } }
    function tryClose() { if (keepOpen) shake(); else close() }
    function shake() { shakeAnim.restart() }
    // the primary ActionButton(s) currently on screen in the dialog
    function primaries(item, out) {
        for (const c of item.children) {
            if (!c.visible) continue
            if (c.variant === "primary" && c.interactive && !c.busy && typeof c.clicked === "function") out.push(c)
            else primaries(c, out)
        }
        return out
    }
    function accept() {
        const focus = card.Window.activeFocusItem
        if (focus && focus.cursorPosition !== undefined) return false   // a text field: it handles Enter itself
        const p = primaries(inner, [])
        if (p.length !== 1) return false
        p[0].clicked()
        return true
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 100
    Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }

    Rectangle {
        anchors.fill: parent
        radius: Compositor.appRadius
        color: Colors.shade(0.4)
        // hover and the wheel stop here too: rows behind the dialog mustn't light
        // up, and a scroll that runs past the dialog's end mustn't scroll the view
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.tryClose(); onWheel: w => w.accepted = true }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, root.width - 40)
        height: Math.min(inner.childrenRect.height + 36, root.height - 40)
        radius: Properties.popupRadius + 6
        color: Colors.surfacePopover
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        scale: root.shown ? 1 : 0.95
        clip: true
        Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
        // content that appears / goes (hints, server settings, …) grows the card smoothly
        Behavior on height { enabled: root.opacity === 1; NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }

        Keys.onEscapePressed: root.tryClose()
        Keys.onReturnPressed: e => e.accepted = root.enterAccepts && root.accept()
        Keys.onEnterPressed: e => e.accepted = root.enterAccepts && root.accept()

        transform: Translate { id: shakeX }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: shakeX; property: "x"; to: -6; duration: 60 }
            NumberAnimation { target: shakeX; property: "x"; to: 3; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 40 }
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => w.accepted = true }   // clicks on the card don't close it

        // scrolls when the content is taller than the window. The clip edge
        // sits 8 px outside the content (10 + 8 = the 18 px card padding), so
        // buttons that grow on hover near the edge aren't cut off.
        Flickable {
            anchors.fill: parent
            anchors.margins: Tokens.space.s10
            contentHeight: inner.childrenRect.height + 16
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: contentHeight > height
            Item {
                id: inner
                x: 8
                y: 8
                width: parent.width - 16
                height: childrenRect.height
            }
        }
    }
}
