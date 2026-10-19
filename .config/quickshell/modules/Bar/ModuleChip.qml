import QtQuick
import qs.services

// A module in the bar's edit toolbar; drag it onto the bar (BarEditLayer).
Rectangle {
    id: chip
    property Item editor
    property string modId
    property bool placed: false         // on the bar already, just not showing

    readonly property var mod: BarLayout.module(modId)
    readonly property bool dragged: editor.dragId === modId

    width: chipRow.implicitWidth + 18
    height: 30
    radius: 9
    opacity: dragged ? 0.35 : placed ? 0.75 : 1
    color: mouse.containsMouse ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.18) : Colors.fade(0.05)
    border.width: 1
    border.color: mouse.containsMouse ? Colors.color6 : placed ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.35) : Colors.fade(0.12)
    Behavior on color { ColorAnimation { duration: Anim.color } }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 6
        Text { text: chip.mod.icon; color: chip.placed ? Colors.color6 : Colors.ink; font.pixelSize: 13; font.family: Properties.fontFamily }
        Text { text: chip.mod.name; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
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
            if (chip.editor.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 4)
                chip.editor.begin(chip.modId, chip, press.x, press.y)
            if (chip.dragged) chip.editor.track(mapToItem(chip.editor.overlay, m.x, m.y))
        }
        onReleased: chip.editor.finish()
        onCanceled: chip.editor.cancel()
    }
}
