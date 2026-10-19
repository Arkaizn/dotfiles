import QtQuick
import QtQuick.Layouts
import qs.services

// Drag state + ghost for a group of BarZones on a layout page (dashboard /
// control center): BarZone { page: board } and BarChip use it like the bar
// layout page itself. The page says what a chip shows (info) and what a drop
// does (place).
//   ChipBoard { id: board; info: id => …; place: (id, zone, index) => …
//               BarZone { zone: "a"; title: "…"; ids: […]; page: board } }
Item {
    id: board

    property var info: id => ({ icon: "", name: id })
    property var place: (id, zone, index) => {}
    property string addZone: "add"            // where + on a hidden chip puts it
    property int addIndex: 0
    readonly property bool editable: true
    default property alias content: col.data

    implicitHeight: col.implicitHeight

    property string dragId: ""
    property string dropZone: "-"
    property int dropIndex: 0
    property alias ghost: ghost

    function prepareDrag(chip) {
        const p = chip.mapToItem(board, 0, 0)
        ghost.x = p.x
        ghost.y = p.y
        ghost.modId = chip.modId
    }
    function startDrag(id, zone) { dragId = id; dropZone = "-" }
    function endDrag() {
        if (dragId === "") return
        ghost.Drag.drop()
        cancelDrag()
    }
    function cancelDrag() { dragId = ""; dropZone = "-" }
    function dropHere() { if (dragId !== "" && dropZone !== "-") place(dragId, dropZone, dropIndex) }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10
    }

    LayoutGhost {
        id: ghost
        active: board.dragId !== ""
        info: board.info(modId)
    }
}
