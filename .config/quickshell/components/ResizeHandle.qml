import QtQuick
import qs.services

// A grip on a panel's edge for resizing it live (Part 6). Reports how far it
// was dragged since the press; the owner turns that into a size (Snap.resize)
// and saves it on release. Only a small pill shows, no outline while dragging.
//   ResizeHandle { horizontal: true; onMoved: d => w = Snap.resize(startW, d * 2, …); onDone: save() }
Item {
    id: root
    property bool horizontal: true        // true: drags left / right (width), false: up / down
    property real sign: 1                 // -1: dragging towards negative grows it (a left / top edge)
    signal started()
    signal moved(real delta)              // since the press, in the grow direction
    signal done()

    width: horizontal ? 18 : 64
    height: horizontal ? 64 : 18

    Rectangle {
        anchors.centerIn: parent
        width: root.horizontal ? 5 : 44
        height: root.horizontal ? 44 : 5
        radius: 2.5
        color: Colors.fade(area.pressed ? 0.9 : area.containsMouse ? 0.7 : 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.horizontal ? Qt.SizeHorCursor : Qt.SizeVerCursor
        property point press
        onPressed: m => { press = mapToItem(null, m.x, m.y); root.started() }
        onPositionChanged: m => {
            if (!pressed) return
            const p = mapToItem(null, m.x, m.y)
            root.moved(root.sign * (root.horizontal ? p.x - press.x : p.y - press.y))
        }
        onReleased: root.done()
        onCanceled: root.done()
    }
}
