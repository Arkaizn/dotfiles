import QtQuick
import qs.services

// A chip you drag out of an edit toolbar into place (bar modules, control
// center buttons / cards, dashboard cards). The look and the drag gesture are
// here; the editor it belongs to is wired up by the caller:
//
//   DragChip {
//       icon: info.icon; text: info.name
//       dragged: editor.dragId === myId
//       placed: false                    // already on the bar, just hidden: dimmer, accent outline
//       deletable: false                 // shows a trash glyph → deleteClicked()
//       onDragBegin: (x, y) => editor.begin(myId, this, x, y)
//       onDragMove: p => editor.track(mapToItem(editor.overlay, p.x, p.y))
//       onDragEnd: editor.finish()
//       onDragCancel: editor.cancel()
//   }
Rectangle {
    id: chip

    property string icon: ""
    property string text: ""
    property bool dragged: false
    property bool placed: false
    property bool deletable: false
    signal dragBegin(real x, real y)     // press point, in chip coordinates
    signal dragMove(point p)             // pointer, in chip coordinates
    signal dragEnd()
    signal dragCancel()
    signal deleteClicked()

    implicitWidth: chipRow.implicitWidth + 16
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight
    radius: Tokens.radius.md
    opacity: dragged ? Tokens.alpha.dragged : placed ? 0.75 : 1
    color: mouse.containsMouse ? Colors.alpha(Colors.accent, 0.18) : Colors.fade(0.05)
    border.width: Tokens.border.thin
    border.color: mouse.containsMouse ? Colors.accent : placed ? Colors.alpha(Colors.accent, 0.35) : Colors.fade(0.12)
    Behavior on color { ColorAnimation { duration: Anim.fast } }
    Accessible.role: Accessible.Button
    Accessible.name: text

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: chip.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point press: Qt.point(0, 0)
        property bool started: false
        onPressed: m => { press = Qt.point(m.x, m.y); started = false }
        onPositionChanged: m => {
            if (!pressed) return
            if (!started && Math.hypot(m.x - press.x, m.y - press.y) > 4) {
                started = true
                chip.dragBegin(press.x, press.y)
            }
            if (chip.dragged) chip.dragMove(Qt.point(m.x, m.y))
        }
        onReleased: chip.dragEnd()
        onCanceled: chip.dragCancel()
    }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Tokens.space.s6
        Text { text: chip.icon; color: chip.placed ? Colors.accent : Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
        Text { text: chip.text; color: Colors.ink; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
        Text {
            visible: chip.deletable
            text: "󰆴"
            color: delMouse.containsMouse ? Colors.danger : Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            MouseArea {
                id: delMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.deleteClicked()
            }
        }
    }
}
