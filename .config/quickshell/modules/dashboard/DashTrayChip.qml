import QtQuick
import qs.services

// A hidden dashboard card in the edit bar: drag it into a column.
Rectangle {
    id: chip
    required property var dash          // the dashboard (drag state)
    required property string cardId

    readonly property var info: PanelLayout.dashCard(cardId)
    readonly property bool dragged: dash.dragId === cardId

    implicitWidth: chipRow.implicitWidth + 16
    implicitHeight: 26
    radius: 8
    opacity: dragged ? 0.35 : 1
    color: mouse.containsMouse ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18) : Colors.fade(0.05)
    border.width: 1
    border.color: mouse.containsMouse ? Colors.color6 : Colors.fade(0.12)
    Behavior on color { ColorAnimation { duration: Anim.color } }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        Text { text: chip.info.icon; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
        Text { text: chip.info.name; color: Colors.ink; font.pixelSize: 11; font.family: Properties.fontFamily }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: chip.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point press: Qt.point(0, 0)
        onPressed: m => press = Qt.point(m.x, m.y)
        onPositionChanged: m => {
            if (!pressed) return
            if (chip.dash.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 4)
                chip.dash.beginDrag(chip.cardId, chip, press.x, press.y)
            if (chip.dragged) chip.dash.track(mapToItem(chip.dash.overlay, m.x, m.y))
        }
        onReleased: chip.dash.endDrag()
        onCanceled: chip.dash.cancelDrag()
    }
}
