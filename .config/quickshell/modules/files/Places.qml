import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons

// The sidebar's places: Recent and Starred, home and the XDG folders, the
// trash (that part in your order: drag an entry up / down), the GTK bookmarks
// (dragged into an order, or into groups: a colour, a name, folding open and
// shut — right-click a bookmark → Move to group), the drives with how full they are (and the ones
// not mounted yet: a click mounts them), saved servers and the network. The
// open folder has one highlight that slides from place to place, like Mail's
// folder list.
//   Places { places: <backend "places" reply>; servers: [{ uri, name }]; path: folder.path
//            onPicked: p => go(p)   (also "recent:", "starred:", "trash:", "network:")
//            onMountRequested: volume => … · onEjectRequested: mount => … · onServerPicked: uri => …
//            onConnectRequested }
Flickable {
    id: root

    property var places: null
    property string path: ""
    signal picked(string path)
    signal context(var place, Item item, real x, real y)     // right-click on a place
    signal dropped(string path, var drop)                    // files dropped on a place
    signal mountRequested(var volume)                        // a drive that isn't mounted yet
    signal ejectRequested(var mount)
    signal serverPicked(string uri)
    signal connectRequested()
    property var servers: []
    required property var app             // FilesApp: the sidebar's order, groups (state file), the backend
    readonly property Item pickItem: pick   // the sliding highlight (BookmarkEntry points it at itself)

    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: SlimScrollBar { id: bar }
    SmoothWheel { flick: root; step: 100 }

    // Settings.files.side*: what's shown (right-click → Hide; Preferences → Sidebar)
    function shown(key) { return Settings.files[key] ?? true }
    function sideKeyOf(kind) { return "side" + kind.charAt(0).toUpperCase() + kind.slice(1) }
    // the icon theme's picture for a place (Settings.files.iconTheme), "" = the glyph
    readonly property bool themed: Settings.files.iconTheme ?? false
    function themeIcon(name) { return themed ? Quickshell.iconPath(name, true) : "" }
    readonly property var themeNames: ({ recent: "document-open-recent", starred: "starred", home: "user-home", desktop: "user-desktop",
        documents: "folder-documents", downloads: "folder-download", music: "folder-music", pictures: "folder-pictures",
        videos: "folder-videos", trash: "user-trash", bookmark: "folder", root: "drive-harddisk", drive: "drive-harddisk",
        usb: "drive-removable-media", network: "network-workgroup", server: "folder-remote" })

    // ── The top part, in your order (app.sideOrder) ──
    readonly property var topList: {
        const pl = places, out = []
        for (const id of app.sideOrder) {
            if (id === "recent") out.push({ id: id, label: "Recent", icon: "\u{F02DA}", target: "recent:", sideKey: "sideRecent" })
            else if (id === "starred") out.push({ id: id, label: "Starred", icon: "\u{F04CE}", target: "starred:", sideKey: "sideStarred" })
            else if (id === "trash") out.push({ id: id, label: "Trash", icon: FmIcons.g.trash, target: "trash:", sideKey: "sideTrash", drop: "trash:" })
            else if (id === "home") { if (pl?.home) out.push({ id: id, label: "Home", icon: Icons.get("files.home"), target: pl.home, path: pl.home, sideKey: "sideHome", drop: pl.home }) }
            else {
                const x = (pl?.xdg ?? []).find(d => d.kind === id)
                if (x) out.push({ id: id, label: x.name, icon: Icons.get("files." + id), target: x.path, path: x.path, sideKey: sideKeyOf(id), drop: x.path })
            }
        }
        return out
    }
    // ── Bookmarks: the top-level ones, then each group with its own ──
    readonly property var marks: places?.bookmarks ?? []
    function groupOf(b) { const g = app.groupPins[b.uri]; return g && app.groups.some(x => x.id === g) ? g : "" }
    readonly property var looseMarks: marks.filter(b => groupOf(b) === "")
    function marksIn(id) { return marks.filter(b => groupOf(b) === id) }

    // ── Dragging an entry: where it lands ──
    property var dragging: null            // { kind: top | bookmark | group, id }
    property real lineY: -1                // the insert line (content coordinates)
    function entries(item, out) {
        for (const c of item.children) {
            if (c.dragKind !== undefined && c.dragKind !== "" && c.visible) out.push(c)
            else if (c.children && c.children.length) entries(c, out)
        }
        return out
    }
    // the entry under scene y that `kind` may land on, and above or below its middle
    function landing(kind, sceneY) {
        const y = root.contentItem.mapFromItem(null, 0, sceneY).y
        for (const e of entries(col, [])) {
            const top = e.mapToItem(root.contentItem, 0, 0).y
            if (y < top || y > top + e.height) continue
            const ok = kind === "top" ? e.dragKind === "top"
                     : kind === "group" ? e.dragKind === "group"
                     : e.dragKind === "bookmark" || e.dragKind === "group"
            if (!ok || (e.dragKind === kind && e.dragId === dragging?.id)) return null
            return { entry: e, above: y < top + e.height / 2, top: top }
        }
        return null
    }
    function moved(kind, id, sceneY) {
        dragging = { kind: kind, id: id }
        const l = landing(kind, sceneY)
        lineY = !l ? -1 : (kind === "bookmark" && l.entry.dragKind === "group") ? -1 : (l.above ? l.top : l.top + l.entry.height)
        dropGroup = l && kind === "bookmark" && l.entry.dragKind === "group" ? l.entry.dragId : ""
    }
    property string dropGroup: ""          // a bookmark dragged over a group header: it goes in there
    function done(kind, id, sceneY) {
        const l = landing(kind, sceneY)
        dragging = null
        lineY = -1
        dropGroup = ""
        if (!l) return
        const t = l.entry
        if (kind === "top") {
            const list = app.sideOrder.filter(x => x !== id)
            list.splice(list.indexOf(t.dragId) + (l.above ? 0 : 1), 0, id)
            app.setSideOrder(list)
        } else if (kind === "group") {
            app.moveGroup(id, t.dragId)
        } else if (t.dragKind === "group") {
            app.pinTo(id, t.dragId)
        } else {
            // among the bookmarks: that place in GTK's list, and the target's group
            const uris = marks.map(b => b.uri).filter(u => u !== id)
            uris.splice(uris.indexOf(t.dragId) + (l.above ? 0 : 1), 0, id)
            app.pinTo(id, t.group)
            app.backend.request("bookmark", { action: "order", uris: uris }, { error: () => {} })
        }
    }

    function used(m) { return m && m.size > 0 ? 1 - m.free / m.size : -1 }

    // the open folder's highlight (the entries point it at themselves)
    Rectangle {
        id: pick
        property Item target: null
        readonly property bool on: target !== null && target.current && target.visible
        readonly property point at: {
            let x = 0, y = 0
            for (let it = target; it && it !== root.contentItem; it = it.parent) { x += it.x; y += it.y }
            return Qt.point(x, y)
        }
        x: at.x
        y: at.y
        width: target?.width ?? 0
        height: target?.height ?? 0
        radius: Tokens.radius.lg
        border.width: Tokens.border.control
        border.color: Colors.fade(0.24)
        gradient: ButtonGradient { hovered: true }
        opacity: on ? 1 : 0
        scale: travel.running ? 0.97 : 1
        onTargetChanged: if (opacity > 0) travel.restart()
        Timer { id: travel; interval: Anim.normal }   // the squash while the highlight travels
        readonly property bool slides: opacity > 0
        Behavior on x { enabled: pick.slides; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        Behavior on y { enabled: pick.slides; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        Behavior on width { enabled: pick.slides; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        Behavior on height { enabled: pick.slides; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        Behavior on opacity { NumberAnimation { duration: Anim.normal } }
        Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
    }

    ColumnLayout {
        id: col
        width: root.width - (bar.visible ? bar.width - 2 : 0)
        spacing: Tokens.space.s1

        Repeater {
            model: root.topList
            PlaceEntry {
                id: topEntry
                required property var modelData
                dragKind: "top"
                dragId: modelData.id
                onDragMoved: y => root.moved("top", dragId, y)
                onDragDone: y => root.done("top", dragId, y)
                icon: modelData.icon
                iconSource: root.themeIcon(root.themeNames[modelData.id] ?? "folder")
                label: modelData.label
                visible: root.shown(modelData.sideKey)
                glow: pick
                current: root.path === modelData.target
                onClicked: root.picked(modelData.target)
                onContext: (x, y) => root.context(Object.assign({ sideKey: modelData.sideKey, name: modelData.label },
                                                                modelData.path ? { path: modelData.path } : {}), topEntry, x, y)
                dropPath: modelData.drop ?? ""
                onDropped: drop => root.dropped(dropPath, drop)
            }
        }

        SideLabel { text: "BOOKMARKS"; Layout.topMargin: Tokens.space.s12; visible: (root.marks.length > 0 || root.app.groups.length > 0) && root.shown("sideBookmarks") }
        Repeater {
            model: root.looseMarks
            BookmarkEntry { places: root }
        }
        Repeater {
            model: root.app.groups
            ColumnLayout {
                id: grp
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                visible: root.shown("sideBookmarks")
                PlaceEntry {
                    id: header
                    dragKind: "group"
                    dragId: grp.modelData.id
                    onDragMoved: y => root.moved("group", dragId, y)
                    onDragDone: y => root.done("group", dragId, y)
                    label: grp.modelData.name
                    dot: Colors[grp.modelData.color] ?? Colors.accent
                    fold: grp.modelData.open ? "open" : "closed"
                    // a bookmark dragged over it: it goes in here
                    dropRing: root.dropGroup === dragId
                    onClicked: root.app.editGroup(grp.modelData.id, { open: !grp.modelData.open })
                    onContext: (x, y) => root.context({ group: grp.modelData }, header, x, y)
                }
                Repeater {
                    model: grp.modelData.open ? root.marksIn(grp.modelData.id) : []
                    BookmarkEntry { places: root; indent: true; group: grp.modelData.id }
                }
            }
        }
        SideLabel { text: "DRIVES"; Layout.topMargin: Tokens.space.s12; visible: root.places !== null && root.shown("sideDrives") }
        PlaceEntry {
            id: rootEntry
            readonly property var place: root.places?.root ?? null
            visible: place !== null && root.shown("sideDrives")
            icon: Icons.get("files.root")
            iconSource: root.themeIcon("drive-harddisk")
            label: "Computer"
            used: root.used(place)
            tooltip: place?.size > 0 ? Format.bytes(place.free) + " free of " + Format.bytes(place.size) : ""
            glow: pick
            current: root.path === "/"
            onClicked: root.picked("/")
            onContext: (x, y) => root.context(Object.assign({ sideKey: "sideDrives" }, place), rootEntry, x, y)
            dropPath: "/"
            onDropped: drop => root.dropped(dropPath, drop)
        }
        Repeater {
            model: root.places?.mounts ?? []
            PlaceEntry {
                id: mountEntry
                required property var modelData
                visible: root.shown("sideDrives")
                icon: modelData.icon.includes("usb") || modelData.icon.includes("removable") ? Icons.get("files.usb") : Icons.get("files.drive")
                iconSource: root.themeIcon(modelData.icon.includes("usb") || modelData.icon.includes("removable") ? "drive-removable-media" : "drive-harddisk")
                label: modelData.name
                used: root.used(modelData)
                interactive: !!modelData.path
                muted: !modelData.path
                tooltip: !modelData.path ? "Not reachable as a folder yet"
                       : modelData.size > 0 ? Format.bytes(modelData.free) + " free of " + Format.bytes(modelData.size) : modelData.path
                glow: pick
                current: !!modelData.path && root.path === modelData.path
                onClicked: root.picked(modelData.path)
                onContext: (x, y) => root.context(Object.assign({ sideKey: "sideDrives" }, modelData), mountEntry, x, y)
                actionIcon: modelData.canEject ? FmIcons.g.eject : modelData.canUnmount ? "\u{F0377}" : ""
                actionTip: modelData.canEject ? "Eject" : "Unmount"
                onAction: root.ejectRequested(modelData)
                dropPath: modelData.path ?? ""
                onDropped: drop => root.dropped(dropPath, drop)
            }
        }
        // drives, partitions, phones that aren't mounted: a click mounts (and opens) them
        Repeater {
            model: root.places?.volumes ?? []
            PlaceEntry {
                required property var modelData
                visible: root.shown("sideDrives")
                icon: modelData.encrypted ? FmIcons.g.lock : modelData.icon.includes("phone") || modelData.icon.includes("multimedia") ? "\u{F011C}"
                    : modelData.icon.includes("camera") ? "\u{F0100}" : Icons.get("files.usb")
                label: modelData.name
                muted: true
                tooltip: modelData.encrypted ? "Encrypted — click to unlock" : "Not mounted — click to open"
                onClicked: root.mountRequested(modelData)
            }
        }

        SideLabel { text: "NETWORK"; Layout.topMargin: Tokens.space.s12; visible: root.shown("sideNetwork") }
        Repeater {
            model: root.servers
            PlaceEntry {
                id: serverEntry
                required property var modelData
                visible: root.shown("sideNetwork")
                icon: "\u{F048B}"
                label: modelData.name
                tooltip: modelData.uri
                onClicked: root.serverPicked(modelData.uri)
                onContext: (x, y) => root.context({ server: modelData.uri, name: modelData.name }, serverEntry, x, y)
            }
        }
        PlaceEntry {
            icon: "\u{F0318}"
            iconSource: root.themeIcon("network-workgroup")
            label: "Network"
            visible: root.shown("sideNetwork")
            onContext: (x, y) => root.context({ sideKey: "sideNetwork", name: "Network" }, this, x, y)
            glow: pick
            current: root.path === "network:"
            onClicked: root.picked("network:")
        }
        PlaceEntry {
            icon: "\u{F0415}"
            label: "Connect to server…"
            visible: root.shown("sideNetwork")
            onClicked: root.connectRequested()
        }
    }

    // where a dragged entry would land
    Rectangle {
        visible: root.lineY >= 0
        x: Tokens.space.s8
        y: root.lineY - height / 2
        width: col.width - 2 * Tokens.space.s8
        height: Tokens.border.selected
        radius: height / 2
        color: Colors.accent
    }
}
