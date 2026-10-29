import QtQuick
import qs.services
import QtQuick.Controls

// Slim scrollbar: hidden until scrolling / hovered, draggable; not there at all
// when everything fits (nothing under it loses its hover).
//   Flickable { ScrollBar.vertical: CalScrollBar {} }
ScrollBar {
    id: bar
    policy: ScrollBar.AsNeeded
    implicitWidth: 12
    padding: 3
    minimumSize: 0.08
    visible: size < 1

    // the wheel scrolls by moving contentY (SmoothWheel), which doesn't make the bar
    // "active": any change of the position shows it for a moment
    property bool moved: false
    onPositionChanged: { moved = true; hideTimer.restart() }
    Timer { id: hideTimer; interval: 900; onTriggered: bar.moved = false }

    contentItem: Rectangle {
        implicitWidth: 6
        radius: 3
        color: Colors.fade(bar.pressed ? 0.5 : bar.hovered ? 0.35 : 0.2)
        opacity: bar.size < 1 ? (bar.active || bar.moved || bar.hovered || bar.pressed ? 1 : 0) : 0
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    background: Item {}
}
