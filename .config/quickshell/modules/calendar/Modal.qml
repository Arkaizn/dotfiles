import QtQuick
import qs.services

// Dimmed overlay with a card in the middle; click outside or Esc closes it.
//   Modal { id: m; cardWidth: 460; …content… }   m.open() / m.close()
Item {
    id: root

    property bool shown: false
    property int cardWidth: 460
    // unsaved input: clicks outside / Esc shake the card instead of closing it
    property bool keepOpen: false
    default property alias content: inner.data
    signal closed()

    function open() { shown = true; card.forceActiveFocus() }
    function close() { if (shown) { shown = false; closed() } }
    function tryClose() { if (keepOpen) shake(); else close() }
    function shake() { shakeAnim.restart() }

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 100
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: Compositor.appRadius
        color: "#66000000"
        MouseArea { anchors.fill: parent; onClicked: root.tryClose() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, root.width - 40)
        height: Math.min(inner.childrenRect.height + 36, root.height - 40)
        radius: Properties.popupRadius + 6
        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        scale: root.shown ? 1 : 0.95
        clip: true
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: root.tryClose()

        transform: Translate { id: shakeX }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: shakeX; property: "x"; to: -6; duration: 60 }
            NumberAnimation { target: shakeX; property: "x"; to: 3; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 40 }
        }
        MouseArea { anchors.fill: parent }   // clicks on the card don't close it

        // scrolls when the content is taller than the window. The clip edge
        // sits 8 px outside the content (10 + 8 = the 18 px card padding), so
        // buttons that grow on hover near the edge aren't cut off.
        Flickable {
            anchors.fill: parent
            anchors.margins: 10
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
