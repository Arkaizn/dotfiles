import QtQuick
import qs.components
import qs.services

// A hidden card / button in the control center's edit bar: drag it into place.
// An own card that's hidden can also be deleted here (trash).
DragChip {
    id: chip
    required property var host          // the control center
    property string kind: "item"        // "card" | "item"
    property string chipId

    readonly property var info: kind === "card" ? PanelLayout.ccCard(chipId) : PanelLayout.item(chipId)

    icon: info?.icon ?? ""
    text: info?.name ?? ""
    dragged: (host?.dragId ?? "") === chipId
    deletable: kind === "card" && info?.custom === true
    onDragBegin: (x, y) => { if (host.dragId === "") host.beginDrag(kind, chipId, chip, x, y) }
    onDragMove: p => host.track(mapToItem(host.overlay, p.x, p.y))
    onDragEnd: host.endDrag()
    onDragCancel: host.cancelDrag()
    onDeleteClicked: PanelLayout.ccDelete(chipId)
}
