import QtQuick
import qs.services
import "lib/FmIcons.js" as FmIcons

// A bookmark in the sidebar (GTK's list): at the top level or in a group (indent).
// Dragged up / down it changes places (and group); onto a group header it goes in.
//   BookmarkEntry { places: <Places>; modelData; group: "<id>" | "" }
PlaceEntry {
    id: b
    required property var places
    required property var modelData
    property string group: ""
    // in a group: its folder glyph in the group's colour
    tint: { const g = group ? places.app.groups.find(x => x.id === group) : null; return g ? Colors[g.color] ?? Colors.accent : "transparent" }

    dragKind: "bookmark"
    dragId: modelData.uri
    onDragMoved: y => places.moved("bookmark", dragId, y)
    onDragDone: y => places.done("bookmark", dragId, y)
    visible: places.shown("sideBookmarks")
    icon: modelData.remote ? FmIcons.g.link : Icons.get("files.bookmark")
    iconSource: places.themeIcon(modelData.remote ? "folder-remote" : "folder")
    label: modelData.name
    // a missing folder stays listed, dimmed; a server bookmark connects
    muted: modelData.missing === true
    tooltip: modelData.remote ? modelData.uri : modelData.missing ? "This folder doesn't exist any more" : ""
    glow: places.pickItem
    current: !modelData.remote && places.path === modelData.path
    onClicked: modelData.remote ? places.serverPicked(modelData.uri) : places.picked(modelData.path)
    onContext: (x, y) => places.context(Object.assign({ bookmark: true, sideKey: "sideBookmarks", group: b.group }, modelData), b, x, y)
    dropPath: modelData.remote || modelData.missing ? "" : modelData.path
    onDropped: drop => places.dropped(dropPath, drop)
}
