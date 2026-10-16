import QtQuick
import QtQuick.Controls

// Slim scrollbar: faint until hovered / scrolling, draggable.
//   Flickable { ScrollBar.vertical: CalScrollBar {} }
ScrollBar {
    id: bar
    policy: ScrollBar.AsNeeded
    implicitWidth: 12
    padding: 3
    minimumSize: 0.08

    contentItem: Rectangle {
        implicitWidth: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, bar.pressed ? 0.5 : bar.hovered ? 0.35 : 0.2)
        opacity: bar.size < 1 ? (bar.active || bar.hovered ? 1 : 0.55) : 0
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    background: Item {}
}
