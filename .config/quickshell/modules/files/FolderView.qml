import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons
import "lib/FmZoom.js" as FmZoom
import "lib/FmSelect.js" as FmSelect
import "lib/FmColumns.js" as FmColumns
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath
import "lib/FmDrop.js" as FmDrop

// The open folder's items as a list (columns, click a header to sort) or a
// grid. Only the rows on screen exist (ListView / GridView reuse them).
// Selection like Nautilus (FmSelect): click = only it, Ctrl+click toggles,
// Shift+click / Shift+arrows a range, a click on the background clears;
// double-click / Enter opens. The cursor (`currentIndex`) is where keys move from.
// Rubber band: drag from the background (in the list: from a row's empty part,
// right of its name) — Ctrl / Shift add to the selection; near the top / bottom
// edge it scrolls. Dragging an item (its icon / name) drags the selection out:
// to other apps as file URIs, to a folder here (dropRequested). A drop onto a
// folder's row goes into that folder, elsewhere into the open one.
//
//   FolderView { folder; mode: "list" | "grid"; iconSize; sortBy; reverse; zoomKeys; columns: [ids]
//                onActivated: i => …; onMiddleClicked: i => …
//                onContextRequested: (i, item, x, y) => …   (i = -1: the background)
//                onColumnMenuRequested: (id, item, x, y) => …   (right-click on the column heads)
//                onSortRequested: by => …; onZoomRequested: size => …
//                onDropRequested: (drop, dir) => …   (dir "": the open folder) · onDragStarted / onDragEnded
//                cut: { path: true } (shown faded) }
//   setCurrent(i) · step(n, extend) (rows; grid: ±1 sideways) · stepRows(n, extend) · page(dir, extend)
//   first(extend) · last(extend) · selectOnly(i) · selectAll() · clearSelection() · invertSelection()
//   selectMatching(re) → how many
//   selection { key: true } (key: a name, a path in search results) · selCount · selectedItems()
//   folder: an FmFolder or an FmSearch (search results: the Location column comes first)
//   singleClick: a plain click opens · thumbFor(path, type, mtime, size, px) → url (thumbVersion: they came in)
//   enter(dx)   the folder comes in (a new folder, a tab switch): fades in, slides from dx
// Icon size (D0-9): Ctrl + wheel over it; Ctrl +/−/0 while `zoomKeys` (the
// pointer is over it, or away from the window: ZoomArea.keysOwner); a pinch.
// Touchpad: two fingers sideways = back / forward (swiped). A drag resting on a
// folder for a moment opens it (springOpen), like Nautilus' spring-loaded folders.
Rectangle {
    id: root

    required property var folder
    property string mode: "list"
    property int iconSize: FmZoom.def.list
    property string sortBy: "name"
    property bool reverse: false
    property bool zoomKeys: false
    property var columns: FmColumns.def
    signal activated(int index)
    signal middleClicked(int index)
    signal contextRequested(int index, Item item, real x, real y)
    signal columnMenuRequested(string id, Item item, real x, real y)
    signal sortRequested(string by)
    signal zoomRequested(int size)
    signal dropRequested(var drop, string dir)
    signal dragStarted(var paths)
    signal dragEnded()
    signal swiped(int dir)                // the touchpad: two fingers sideways (-1 back, +1 forward)
    signal springOpen(string path)        // a drag rested on a folder: go in
    signal pressed()                      // any press on the files (the window takes the keyboard back)
    property var cut: ({})
    property bool singleClick: false
    property var thumbFor: null
    property int thumbVersion: 0
    property string caption: "none"            // grid: size | date | type under the name
    // special folders (home, Desktop, Downloads …): path → kind; they show their own icons
    property var specials: ({})
    function specialGlyph(key, dir) { const k = dir ? specials[pathOfKey(key)] : undefined; return k ? Icons.get("files." + k) : "" }
    function specialTheme(key, dir) {
        const k = dir && themed ? specials[pathOfKey(key)] : undefined
        return k ? Quickshell.iconPath(FmIcons.specialTheme[k] ?? "folder", true) : ""
    }
    // the icon theme's picture of an item (Settings.files.iconTheme), "" = the glyph; looked up once per type
    property bool themed: false
    property var _themeCache: ({})
    function themeIcon(dir, type, exec) {
        if (!themed) return ""
        const key = (dir ? "/" : "") + type + (exec ? "*" : "")
        let u = _themeCache[key]
        if (u === undefined) {
            u = ""
            for (const n of FmIcons.themeNames({ dir: dir, type: type, exec: exec })) {
                u = Quickshell.iconPath(n, true)
                if (u) break
            }
            _themeCache[key] = u
        }
        return u
    }
    readonly property bool searching: folder.query !== undefined
    // a selection key → its path (a folder's keys are names, search results' are paths)
    function pathOfKey(k) { return k.startsWith("/") ? k : FmPath.join(folder.path, k) }
    property int dropIndex: -1            // the folder row a drag is over
    property point dropPos: Qt.point(0, 0) // where the pointer is during a drag (the "into" tag follows it)
    property int dropAction: Qt.MoveAction
    property bool draggingOut: false

    readonly property Item view: loader.item
    readonly property int currentIndex: view ? view.currentIndex : -1

    // ── Selection (names, so it survives sorting, reloads and live changes) ──
    property var selection: ({})
    property string anchor: ""
    readonly property int selCount: Object.keys(selection).length
    function _nameAt(i) { return folder.at(i)?.key ?? "" }
    function _set(st) { selection = st.sel; anchor = st.anchor }
    function selectOnly(i) { _set(FmSelect.only(i >= 0 ? _nameAt(i) : "")) }
    function selectAll() { selection = FmSelect.all(folder.count, _nameAt) }
    function clearSelection() { _set({ sel: {}, anchor: "" }) }
    function invertSelection() { selection = FmSelect.invert(selection, folder.count, _nameAt) }
    function selectMatching(re) {
        const sel = FmSelect.matching(folder.count, _nameAt, re)
        selection = sel
        // the cursor on the first match, so the keys go on from there
        for (let i = 0; i < folder.count; i++) if (sel[_nameAt(i)]) { setCurrent(i); anchor = _nameAt(i); break }
        return Object.keys(sel).length
    }
    function selectedItems() {
        const out = []
        for (let i = 0; i < folder.count; i++) { const it = folder.at(i); if (selection[it.key]) out.push(it) }
        return out
    }
    function click(i, button, mods) {
        if (button === Qt.RightButton) {
            // like Nautilus: a right-click on something unselected selects only it
            if (!selection[_nameAt(i)]) selectOnly(i)
            setCurrent(i)
            return
        }
        _set(FmSelect.click({ sel: selection, anchor: anchor }, i, mods, _nameAt, folder.count))
        setCurrent(i)
    }
    // names that went away (live changes, a new listing) leave the selection
    function _prune() {
        const present = {}
        for (let i = 0; i < folder.count; i++) present[folder.at(i).key] = true
        _set(FmSelect.prune({ sel: selection, anchor: anchor }, present))
    }
    Connections {
        target: root.folder
        function onChanged() { root._prune() }
        function onLoaded() { root._prune() }
    }

    radius: Tokens.radius.xl
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    clip: true

    // "today" in the dates moves on
    property real now: Date.now()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    // the chosen columns that fit next to the name (FmColumns: the last ones give way first)
    // (search results: where each one is, first)
    // (the views Recent / Starred / Trash too: where each one is — or was)
    readonly property bool showLoc: searching || (folder.kind !== undefined && folder.kind !== "network")
    readonly property var shownColumns: showLoc ? ["loc"].concat(columns.filter(c => c !== "loc")) : columns
    readonly property var cols: FmColumns.fit(shownColumns, width - iconSize - 2 * Tokens.space.s10, Tokens.size.row)
    readonly property var colIds: shownColumns.filter(id => cols[id] !== undefined)

    function setCurrent(i) {
        if (!view) return
        view.currentIndex = i
        if (i >= 0) view.positionViewAtIndex(i, ItemView.Contain)
    }
    readonly property int columnsGrid: mode === "grid" && view ? Math.max(1, Math.floor(view.width / view.cellWidth)) : 1
    readonly property int pageRows: view ? Math.max(1, Math.floor(view.height / (mode === "grid" ? view.cellHeight : rowHeight))) : 1
    readonly property real rowHeight: Math.max(iconSize, Tokens.font.body) + Tokens.space.s12
    // the cursor moved by a key: the selection follows (Shift: from the anchor to it)
    function _to(i, extend) {
        const n = folder.count
        if (n === 0) return
        i = Math.max(0, Math.min(n - 1, i))
        _set(FmSelect.moveTo({ sel: selection, anchor: anchor }, i, extend, _nameAt, n))
        setCurrent(i)
    }
    // a key with nothing current yet lands on the first item
    function step(n, extend) { _to(currentIndex < 0 ? 0 : currentIndex + n, extend) }
    function stepRows(n, extend) { _to(currentIndex < 0 ? 0 : currentIndex + n * columnsGrid, extend) }
    function page(dir, extend) { _to(currentIndex < 0 ? 0 : currentIndex + dir * pageRows * columnsGrid, extend) }
    function first(extend) { _to(0, extend) }
    function last(extend) { _to(folder.count - 1, extend) }

    // ── Drag and drop ──
    function startDrag(i) {
        if (!selection[_nameAt(i)]) selectOnly(i)
        setCurrent(i)
        const paths = selectedItems().map(it => folder.pathOf(it))
        // a name that isn't valid UTF-8 can't become a URI here: left out of the URI list
        dragger.Drag.mimeData = FmDrop.mime(paths, p => { try { return FmPath.url(p) } catch (e) { return "" } })
        // the pointer carries a picture of it (DragCard): drawn, grabbed, then the drag starts
        const it = folder.at(i)
        dragCard.name = FmFormat.shown(it.name)
        dragCard.count = paths.length
        dragCard.glyph = specialGlyph(it.key, it.dir) || FmIcons.item(it)
        dragCard.glyphColor = it.broken ? Colors.danger : it.dir ? Colors.accent : Colors.fade(0.6)
        dragCard.thumb = (thumbFor && !it.dir ? thumbFor(pathOfKey(it.key), it.type, it.mtime, it.size, Tokens.icon.lg) : "")
                         || specialTheme(it.key, it.dir) || themeIcon(it.dir, it.type, it.exec)
        draggingOut = true
        dragStarted(paths)
        _grabCard(0)
    }
    function _grabCard(tries) {
        // a thumbnail still loading: a frame or two more (then without it)
        if (!dragCard.ready && tries < 10) { Qt.callLater(() => root._grabCard(tries + 1)); return }
        // (at its own size: the drag's image has no pixel ratio, a sharper grab would show bigger)
        const ok = dragCard.grabToImage(res => {
            // let go meanwhile: no drag (one can't start without a button held)
            if (!pointer.pressed) { root._dragOver(); return }
            dragger.Drag.imageSource = res.url
            dragger.Drag.hotSpot = Qt.point(Tokens.space.s12, Tokens.space.s12)
            dragger.Drag.active = true
        })
        if (!ok) dragger.Drag.active = true
    }
    function _dragOver() {
        dragger.Drag.active = false
        dragger.Drag.imageSource = ""
        draggingOut = false
        dragEnded()
    }
    function _dragAt(drag) {
        dropPos = Qt.point(drag.x, drag.y)
        dropAction = drag.proposedAction
        dropIndex = dirAt(drag.x, drag.y)
    }
    // (a binding: a spring-opened folder can put another one under a pointer that didn't move)
    readonly property string dropName: folder.path, dropIndex >= 0 && dropIndex < folder.count ? FmFormat.shown(FmPath.base(_nameAt(dropIndex))) : ""
    onDropNameChanged: if (dropName !== "") dropTag.name = dropName      // (kept while the tag fades out)
    // the folder row under a drag (not one of those being dragged)
    function dirAt(x, y) {
        const h = pointer.hit(x, y)
        const it = h.index >= 0 ? folder.at(h.index) : null
        if (!it || !it.dir) return -1
        return draggingOut && selection[it.key] ? -1 : h.index
    }

    // ── Motion ──
    // a folder is being opened: the old listing dims and drifts away at once (the click shows
    // it was taken), the new one comes in from where that left off (enter) when it's there
    property bool leaving: false
    function leave(dx) {
        if (!visible || Anim.scale === 0) return
        enterAnim.stop()
        leaving = true
        leaveAnim.dx = -dx / 2
        leaveAnim.restart()
    }
    function enter(dx) {
        leaveAnim.stop()
        enterAnim.stop()
        // after leave(): on from the dimmed listing; else from nothing
        enterAnim.from = leaving ? viewport.opacity : 0
        leaving = false
        enterAnim.dx = dx
        enterAnim.start()
    }
    ParallelAnimation {
        id: leaveAnim
        property real dx: 0
        NumberAnimation { target: viewport; property: "opacity"; to: Tokens.alpha.dragged; duration: Anim.fast; easing.type: Anim.exit }
        NumberAnimation { target: shift; property: "x"; to: leaveAnim.dx; duration: Anim.fast; easing.type: Anim.exit }
    }
    ParallelAnimation {
        id: enterAnim
        property real dx: 0
        property real from: 0
        NumberAnimation { target: viewport; property: "opacity"; from: enterAnim.from; to: 1; duration: Anim.normal; easing.type: Anim.standard }
        NumberAnimation { target: shift; property: "x"; from: enterAnim.dx; to: 0; duration: Anim.medium; easing.type: Anim.emphasized }
    }
    // live changes (a file appears, goes) move; whole listings just show
    readonly property bool liveMotion: folder.live && Anim.scale > 0
    property Transition addMotion: Transition {
        enabled: root.liveMotion
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.normal; easing.type: Anim.standard }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Anim.normal; easing.type: Anim.pop }
    }
    property Transition removeMotion: Transition {
        enabled: root.liveMotion
        NumberAnimation { property: "opacity"; to: 0; duration: Anim.fast; easing.type: Anim.exit }
        NumberAnimation { property: "scale"; to: 0.94; duration: Anim.fast; easing.type: Anim.exit }
    }
    property Transition displacedMotion: Transition {
        enabled: root.liveMotion
        NumberAnimation { properties: "x,y"; duration: Anim.normal; easing.type: Anim.emphasized }
        // a row that was mid-way in when it got pushed: finish it
        NumberAnimation { property: "opacity"; to: 1; duration: Anim.normal }
        NumberAnimation { property: "scale"; to: 1; duration: Anim.normal }
    }

    function zoomStep(dir) {
        root.zoomRequested(FmZoom.step(mode, iconSize, dir))
        pill.show()
    }
    Shortcut {
        sequences: ["Ctrl++", "Ctrl+=", "Ctrl+Shift++", "Ctrl+Shift+="]
        enabled: root.zoomKeys
        onActivated: root.zoomStep(1)
        onActivatedAmbiguously: root.zoomStep(1)
    }
    Shortcut { sequences: ["Ctrl+-"]; enabled: root.zoomKeys; onActivated: root.zoomStep(-1) }
    Shortcut { sequences: ["Ctrl+0"]; enabled: root.zoomKeys; onActivated: root.zoomStep(0) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.space.s4
        spacing: 0

        // the list's column heads: click one to sort by it, again to turn the order around;
        // right-click: which columns, their order
        Item {
            visible: root.mode === "list"
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.space.s2
            implicitHeight: heads.implicitHeight
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: m => root.columnMenuRequested("", this, m.x, m.y)
            }
            RowLayout {
                id: heads
                anchors.fill: parent
                anchors.leftMargin: Tokens.space.s10 + root.iconSize + Tokens.space.s10 - Tokens.space.s8
                anchors.rightMargin: Tokens.space.s10 - Tokens.space.s8
                spacing: Tokens.space.s10 - 2 * Tokens.space.s8
                ColumnHead {
                    Layout.fillWidth: true; label: "Name"; active: root.sortBy === "name"; reverse: root.reverse
                    onClicked: root.sortRequested("name")
                    onRightClicked: root.columnMenuRequested("", this, width / 2, height)
                }
                Repeater {
                    model: root.colIds
                    ColumnHead {
                        required property string modelData
                        readonly property var spec: FmColumns.spec(modelData)
                        Layout.preferredWidth: root.cols[modelData] + 2 * Tokens.space.s8
                        label: spec.label
                        alignRight: spec.right === true
                        sortable: spec.sort !== undefined
                        active: spec.sort !== undefined && root.sortBy === spec.sort
                        reverse: root.reverse
                        onClicked: if (spec.sort) root.sortRequested(spec.sort)
                        onRightClicked: root.columnMenuRequested(modelData, this, 0, height)
                    }
                }
            }
        }

        // the pointer area lies under the view: the rows and tiles take no clicks
        // themselves, so presses fall through to it (the scrollbar keeps its own)
        Item {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            transform: Translate { id: shift }

            MouseArea {
                id: pointer
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                preventStealing: true

                property var press: null          // { x, y, index, body, button, mods }
                property bool banding: false
                property bool afterDouble: false
                property var base: ({})            // the selection a Ctrl / Shift band adds to
                property point bandStart: Qt.point(0, 0)    // in content coordinates
                property point at: Qt.point(0, 0)           // the pointer, in viewport coordinates

                // which row is under (x, y), and whether it's on its icon / name (not its empty part)
                function hit(x, y) {
                    const v = root.view
                    if (!v) return { index: -1, body: false }
                    const i = v.indexAt(x + v.contentX, y + v.contentY)
                    if (i < 0) return { index: -1, body: false }
                    const it = v.itemAt(x + v.contentX, y + v.contentY)
                    const p = it ? it.mapFromItem(pointer, x, y) : null
                    // a selected row drags from anywhere on it (Nautilus); an unselected one from its icon / name
                    return { index: i, body: root.selection[root._nameAt(i)] === true || (it && it.onBody ? it.onBody(p.x, p.y) : true) }
                }
                function content(x, y) { const v = root.view; return Qt.point(x + v.contentX - v.originX, y + v.contentY - v.originY) }

                onPressed: m => {
                    root.pressed()
                    const h = hit(m.x, m.y)
                    press = { x: m.x, y: m.y, index: h.index, body: h.body, button: m.button, mods: m.modifiers }
                    banding = false
                    if (m.button === Qt.RightButton) {
                        // like Nautilus: the menu on the press
                        if (h.index >= 0) { root.click(h.index, m.button, m.modifiers); root.contextRequested(h.index, pointer, m.x, m.y) }
                        else { root.clearSelection(); root.contextRequested(-1, pointer, m.x, m.y) }
                        press = null
                    }
                }
                onPositionChanged: m => {
                    at = Qt.point(m.x, m.y)
                    if (!press || press.button !== Qt.LeftButton) return
                    if (!banding) {
                        if (Math.hypot(m.x - press.x, m.y - press.y) < Qt.styleHints.startDragDistance) return
                        if (press.index >= 0 && press.body) {               // an item: drag it (and the rest of the selection) out
                            const i = press.index
                            press = null
                            root.startDrag(i)
                            return
                        }
                        banding = true
                        base = (press.mods & (Qt.ControlModifier | Qt.ShiftModifier)) ? root.selection : ({})
                        bandStart = content(press.x, press.y)
                    }
                    updateBand()
                }
                onReleased: m => {
                    const p = press
                    press = null
                    if (banding) { banding = false; return }
                    if (!p || afterDouble) { afterDouble = false; return }
                    if (p.index >= 0) {
                        if (p.button === Qt.MiddleButton) root.middleClicked(p.index)
                        else {
                            root.click(p.index, p.button, p.mods)
                            // single-click mode: a plain click on an item opens it
                            if (root.singleClick && p.body && p.button === Qt.LeftButton
                                    && !(p.mods & (Qt.ControlModifier | Qt.ShiftModifier))) root.activated(p.index)
                        }
                    } else if (p.button === Qt.LeftButton && !(p.mods & (Qt.ControlModifier | Qt.ShiftModifier))) {
                        root.clearSelection()
                    }
                }
                onDoubleClicked: m => {
                    if (m.button !== Qt.LeftButton || root.singleClick) return
                    const h = hit(m.x, m.y)
                    afterDouble = true
                    if (h.index >= 0) root.activated(h.index)
                }
                onCanceled: { press = null; banding = false }

                function updateBand() {
                    const v = root.view
                    if (!v) return
                    const end = content(at.x, at.y)
                    const r = { x1: bandStart.x, y1: bandStart.y, x2: end.x, y2: end.y }
                    const geo = root.mode === "grid" ? { cellW: v.cellWidth, cellH: v.cellHeight, cols: root.columnsGrid } : { rowH: root.rowHeight }
                    const sel = Object.assign({}, base)
                    const idx = FmSelect.band(r, geo, root.folder.count)
                    for (const i of idx) sel[root._nameAt(i)] = true
                    root.selection = sel
                    if (idx.length) { v.currentIndex = idx[idx.length - 1]; root.anchor = root._nameAt(idx[0]) }
                }
                // near the top / bottom edge the view scrolls while the band is out
                Timer {
                    interval: 16
                    repeat: true
                    running: pointer.banding
                    onTriggered: {
                        const v = root.view, edge = Tokens.size.row
                        if (!v) return
                        const y = pointer.at.y
                        const d = y < edge ? -(edge - y) : y > pointer.height - edge ? y - (pointer.height - edge) : 0
                        if (d === 0) return
                        const max = v.originY + Math.max(0, v.contentHeight - v.height)
                        v.contentY = Math.max(v.originY, Math.min(max, v.contentY + d / 2))
                        pointer.updateBand()
                    }
                }
            }

            Loader {
                id: loader
                anchors.fill: parent
                sourceComponent: root.mode === "grid" ? gridComp : listComp
                // a new view (list ↔ grid) starts on the item the old one was on, and fades in
                property int carry: -1
                onLoaded: {
                    if (carry >= 0) { root.setCurrent(carry); carry = -1 }
                    if (root.visible) root.enter(0)
                }
            }

            // drops: from other apps, other windows, this one
            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    drag.accepted = drag.hasUrls || drag.hasText || FmDrop.imageType(drag.formats) !== ""
                    root._dragAt(drag)
                }
                onPositionChanged: drag => root._dragAt(drag)
                onExited: root.dropIndex = -1
                onDropped: drop => {
                    const i = root.dropIndex
                    root.dropIndex = -1
                    root.dropRequested(drop, i >= 0 ? root.pathOfKey(root._nameAt(i)) : "")
                }
            }
            // what a drag out carries (Drag.Automatic: a real drag, other apps see it)
            Item {
                id: dragger
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
                Drag.proposedAction: Qt.MoveAction
                Drag.onDragFinished: root._dragOver()
            }
            // drawn out of sight, only for the drag's picture
            DragCard { id: dragCard; x: -width - Tokens.size.row * 4; y: 0 }
            // over a folder: a tag hangs under the dragged card saying where it goes (the card
            // itself is a fixed picture once the drag runs; the compositor draws it on top, so
            // the tag sits just below it, hot spot → card's bottom left)
            DropTag {
                id: dropTag
                readonly property bool on: root.dropIndex >= 0
                action: root.dropAction
                x: Math.max(0, Math.min(parent.width - width, root.dropPos.x - Tokens.space.s12))
                y: Math.min(parent.height - height, root.dropPos.y - Tokens.space.s12 + dragCard.height + Tokens.space.s4)
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
                Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.pop } }
            }

            // the rubber band
            Rectangle {
                opacity: pointer.banding && root.view !== null ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
                readonly property point a: root.view ? Qt.point(pointer.bandStart.x - root.view.contentX + root.view.originX,
                                                                pointer.bandStart.y - root.view.contentY + root.view.originY) : Qt.point(0, 0)
                x: Math.min(a.x, pointer.at.x)
                y: Math.min(a.y, pointer.at.y)
                width: Math.abs(pointer.at.x - a.x)
                height: Math.abs(pointer.at.y - a.y)
                radius: Tokens.radius.sm
                color: Colors.alpha(Colors.accent, 0.14)
                border.width: Tokens.border.thin
                border.color: Colors.alpha(Colors.accent, 0.6)
            }
        }
    }
    onModeChanged: loader.carry = currentIndex
    // another source (the folder ↔ its search results ↔ a view): a fresh list. A ListView
    // whose model is swapped kept recycled rows of the old one (search results that stayed
    // on screen in the folder with empty data — "1 Jan 1970", no permissions)
    onFolderChanged: {
        if (!loader.item) return
        loader.active = false
        loader.active = true
    }

    Component {
        id: listComp
        ListView {
            id: list
            model: root.folder.model
            clip: true
            // no drag-to-scroll with the mouse: a drag on the background is the rubber band
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            highlightFollowsCurrentItem: false
            keyNavigationEnabled: false
            reuseItems: true
            cacheBuffer: 800
            ScrollBar.vertical: SlimScrollBar {}
            SmoothWheel { flick: list; step: 100; acceptedModifiers: Qt.NoModifier }      // like the settings sidebar
            add: root.addMotion
            remove: root.removeMotion
            displaced: root.displacedMotion
            delegate: ListRow {
                width: ListView.view.width
                current: ListView.isCurrentItem
                selected: root.selection[key] === true
                faded: root.cut[root.pathOfKey(key)] === true
                dropTarget: root.dropIndex >= 0 && index === root.dropIndex      // (a leaving / pooled row's index is -1 too)
                count: dir ? (root.folder.counts[name] ?? -1) : -1
                thumb: { root.thumbVersion; return (root.thumbFor && !dir ? root.thumbFor(root.pathOfKey(key), type, mtime, size, root.iconSize) : "") || root.specialTheme(key, dir) || root.themeIcon(dir, type, exec) }
                glyph: root.specialGlyph(key, dir)
                iconSize: root.iconSize
                cols: root.cols
                colIds: root.colIds
                here: root.searching ? FmPath.base(root.folder.path) : "/"
                now: root.now
            }
        }
    }
    Component {
        id: gridComp
        GridView {
            id: grid
            model: root.folder.model
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            highlightFollowsCurrentItem: false
            keyNavigationEnabled: false
            reuseItems: true
            cacheBuffer: 800
            // as many tiles as fit, the space shared out between them
            readonly property real minCell: root.iconSize + Tokens.size.row
            cellWidth: width / Math.max(1, Math.floor(width / minCell))
            cellHeight: root.iconSize + Tokens.font.small * 3 + Tokens.space.s24 + (root.caption !== "none" ? Tokens.font.caption + Tokens.space.s4 : 0)
            ScrollBar.vertical: SlimScrollBar {}
            SmoothWheel { flick: grid; step: 100; acceptedModifiers: Qt.NoModifier }      // like the settings sidebar
            add: root.addMotion
            remove: root.removeMotion
            displaced: root.displacedMotion
            delegate: GridTile {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight
                current: GridView.isCurrentItem
                selected: root.selection[key] === true
                faded: root.cut[root.pathOfKey(key)] === true
                dropTarget: root.dropIndex >= 0 && index === root.dropIndex      // (a leaving / pooled row's index is -1 too)
                count: dir ? (root.folder.counts[name] ?? -1) : -1
                thumb: { root.thumbVersion; return (root.thumbFor && !dir ? root.thumbFor(root.pathOfKey(key), type, mtime, size, root.iconSize) : "") || root.specialTheme(key, dir) || root.themeIcon(dir, type, exec) }
                glyph: root.specialGlyph(key, dir)
                iconSize: root.iconSize
                caption: root.caption
            }
        }
    }

    // the touchpad: two fingers sideways, once per swipe (a pause ends a swipe)
    WheelHandler {
        id: swipe
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.TouchPad
        property real acc: 0
        property bool done: false
        onWheel: event => {
            if (Math.abs(event.pixelDelta.x) <= Math.abs(event.pixelDelta.y)) return
            swipeIdle.restart()
            if (done) return
            acc += event.pixelDelta.x
            if (Math.abs(acc) > Tokens.size.row * 4) { root.swiped(acc > 0 ? -1 : 1); done = true }
        }
    }
    Timer { id: swipeIdle; interval: Anim.medium; onTriggered: { swipe.acc = 0; swipe.done = false } }
    // a pinch: a step bigger / smaller each time it has grown / shrunk by a quarter
    PinchHandler {
        target: null
        property real base: 1
        onActiveChanged: base = 1
        onActiveScaleChanged: {
            if (activeScale / base > 1.25) { root.zoomStep(1); base = activeScale }
            else if (activeScale / base < 0.8) { root.zoomStep(-1); base = activeScale }
        }
    }
    // a drag resting on a folder row opens it
    Timer {
        id: spring
        interval: Anim.slower * 2
        onTriggered: if (root.dropIndex >= 0) root.springOpen(root.pathOfKey(root._nameAt(root.dropIndex)))
    }
    onDropIndexChanged: if (dropIndex >= 0) spring.restart(); else spring.stop()

    // Ctrl + wheel: the icon size (the ZoomArea leaves the wheel to us: wheelExcept)
    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        onWheel: event => {
            acc += event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y * 4
            if (Math.abs(acc) >= 120) { root.zoomStep(acc > 0 ? 1 : -1); acc = 0 }
        }
    }

    // nothing to show: loading (after a moment, no flash), failed, empty
    Timer { id: slow; interval: Anim.slower; running: root.folder.loading }
    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Tokens.space.s24, Tokens.size.row * 9)
        visible: root.folder.error !== "" || (root.folder.loading ? !slow.running && root.folder.count === 0 : root.folder.count === 0)
        loading: root.folder.loading && root.folder.error === ""
        tone: root.folder.error !== "" ? "error" : "normal"
        icon: root.folder.error === "" ? FmIcons.g.folderOpen
            : root.folder.errorCode === "denied" ? FmIcons.g.lock : FmIcons.g.alert
        text: root.folder.loading ? (root.searching ? "Searching…" : "Loading…")
            : root.folder.error === "" ? (root.searching ? "Nothing found for “" + FmFormat.shown(root.folder.query) + "”"
                : ({ starred: "Nothing starred yet", recent: "Nothing opened lately", trash: "The trash is empty",
                     network: "Nothing found on the network" })[root.folder.kind ?? ""] ?? "This folder is empty")
            : ({ denied: "No permission to open this folder", missing: "This folder doesn't exist" })[root.folder.errorCode] ?? root.folder.error
        hint: root.folder.error !== "" || root.folder.loading ? ""
            : root.searching ? "Try fewer letters, or the filter button (kind, date)"
            : root.folder.kind === "starred" ? "Right-click a file or folder → Star"
            : root.folder.kind === "network" ? "Or: Connect to server… (smb://, sftp://, …)"
            : root.folder.hiddenCount > 0 ? root.folder.hiddenCount + " hidden — Ctrl+H shows them" : ""
    }

    // still loading after a moment (a big folder, a slow server): a thin bar runs along the top
    // (with items already showing too — they keep coming); a short load never flashes it
    Timer { id: barDelay; interval: Anim.fast; running: root.folder.loading }
    Item {
        id: loadBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.space.s12
        anchors.rightMargin: Tokens.space.s12
        height: Tokens.border.selected
        z: 4
        clip: true
        opacity: root.folder.loading && !barDelay.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
        Rectangle { anchors.fill: parent; radius: height / 2; color: Colors.alpha(Colors.accent, 0.18) }
        Rectangle {
            id: runner
            width: parent.width / 3
            height: parent.height
            radius: height / 2
            color: Colors.accent
            // (without ambient motion: a still third, still saying "loading")
            NumberAnimation on x {
                from: -runner.width; to: loadBar.width
                duration: Anim.slower * 3
                easing.type: Anim.standard
                loops: Animation.Infinite
                running: loadBar.visible && Anim.ambient
            }
        }
    }

    // the icon size, for a moment after a change (like ZoomArea's pill)
    Rectangle {
        id: pill
        function show() { opacity = 1; hideTimer.restart() }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.space.s16
        width: pillRow.implicitWidth + 2 * Tokens.space.s14
        height: Tokens.size.control + Tokens.space.s2
        radius: height / 2
        color: Colors.surfacePopover
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
        Timer { id: hideTimer; interval: Anim.slower * 3; onTriggered: pill.opacity = 0 }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Tokens.space.s8
            Text { text: root.mode === "grid" ? FmIcons.g.grid : FmIcons.g.list; color: Colors.accent; font.pixelSize: Tokens.font.label; font.family: Properties.fontFamily; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Icons " + root.iconSize + " px"; color: Colors.ink; font.pixelSize: Tokens.font.body; font.bold: true; font.family: Properties.fontFamily; anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: root.iconSize !== FmZoom.def[root.mode]
                text: "Ctrl 0 resets"
                color: Colors.fade(0.45); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
