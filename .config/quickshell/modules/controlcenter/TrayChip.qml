import QtQuick
import qs.services

// A hidden card / button in the control center's edit bar: drag it into place.
// An own card that's hidden can also be deleted here (trash).
Rectangle {
    id: chip
    required property var host          // the control center
    property string kind: "item"        // "card" | "item"
    property string chipId

    readonly property var info: kind === "card" ? PanelLayout.ccCard(chipId) : PanelLayout.item(chipId)
    readonly property bool dragged: host.dragId === chipId

    width: chipRow.implicitWidth + 16
    height: 28
    radius: 8
    opacity: dragged ? 0.35 : 1
    color: mouse.containsMouse ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18) : Colors.fade(0.05)
    border.width: 1
    border.color: mouse.containsMouse ? Colors.color6 : Colors.fade(0.12)
    Behavior on color { ColorAnimation { duration: Anim.color } }

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
            if (chip.host.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 4)
                chip.host.beginDrag(chip.kind, chip.chipId, chip, press.x, press.y)
            if (chip.dragged) chip.host.track(mapToItem(chip.host.overlay, m.x, m.y))
        }
        onReleased: chip.host.endDrag()
        onCanceled: chip.host.cancelDrag()
    }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 6
        Text { text: chip.info.icon; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
        Text { text: chip.info.name; color: Colors.ink; font.pixelSize: 11; font.family: Properties.fontFamily }
        Text {
            visible: chip.kind === "card" && chip.info.custom === true
            text: "󰆴"
            color: delMouse.containsMouse ? Colors.red : Colors.fade(0.45)
            font.pixelSize: 12
            font.family: Properties.fontFamily
            MouseArea {
                id: delMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onClicked: PanelLayout.ccDelete(chip.chipId)
            }
        }
    }
}
