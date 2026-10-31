import QtQuick
import qs.components
import qs.services

// A hidden dashboard card in the edit bar: drag it into a column.
DragChip {
    id: chip
    required property var dash          // the dashboard (drag state)
    required property string cardId

    readonly property var info: PanelLayout.dashCard(cardId)

    icon: info?.icon ?? ""
    text: info?.name ?? ""
    dragged: (dash?.dragId ?? "") === cardId
    onDragBegin: (x, y) => { if (dash.dragId === "") dash.beginDrag(cardId, chip, x, y) }
    onDragMove: p => dash.track(mapToItem(dash.overlay, p.x, p.y))
    onDragEnd: dash.endDrag()
    onDragCancel: dash.cancelDrag()
}
