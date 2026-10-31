import QtQuick
import qs.components
import qs.services

// A module in the bar's edit toolbar; drag it onto the bar (BarEditLayer).
DragChip {
    id: chip
    property Item editor
    property string modId

    readonly property var mod: BarLayout.module(modId)

    icon: mod?.icon ?? ""
    text: mod?.name ?? ""
    dragged: (editor?.dragId ?? "") === modId      // null-safe: bindings re-run while a reload tears things down
    onDragBegin: (x, y) => { if (editor.dragId === "") editor.begin(modId, chip, x, y) }
    onDragMove: p => editor.track(mapToItem(editor.overlay, p.x, p.y))
    onDragEnd: editor.finish()
    onDragCancel: editor.cancel()
}
