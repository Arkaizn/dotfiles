import QtQuick
import qs.services
import qs.services.lib
import "lib/FmPath.js" as FmPath
import "lib/FmFormat.js" as FmFormat
import "lib/FmZoom.js" as FmZoom

// One tab of a window: its folder (FmFolder, watched while the tab exists),
// back / forward history, the cursor and the selection, and the folder's view
// (list / grid, sort, icon size: remembered per folder, FilesApp.viewFor).
// The window shows the current tab and sends it the keys.
//
//   FolderTab { app; win; startPath; startSelect }
//   go(path, { select, noHistory, force }) · back() · forward() · up()
//   activate(i) (Enter / double-click) · open(i) · openAside(i) (middle click: a folder in a new tab)
//   selectSoon(names)   select these once they show up (what a paste / new folder made)
//   setView(mode) · setSort(sort) · sortBy(by) · setIconSize(px) · resetView() · makeDefault()
//   path · title · viewMode · sort · iconSize · ownView (this folder has its own view) · info()
//   search(query, { kinds, since }) · endSearch() · searching · folder (the folder, or the
//   search results while a query is set) · openLocation(i) (a result's folder, it selected)
Item {
    id: tab

    required property var app
    required property var win
    property string startPath: ""
    property string startSelect: ""

    // what the view shows: the folder, or the search results while there's a query
    readonly property var folder: special !== "" ? virtualObj : searching && searchObj.query !== "" ? searchObj : folderObj
    readonly property alias dir: folderObj
    // a view that isn't a folder ("recent", "starred", "trash", "network"; go("recent:") …)
    property string special: ""
    readonly property var specialNames: ({ recent: "Recent", starred: "Starred", trash: "Trash", network: "Network" })
    FmVirtual { id: virtualObj; backend: tab.app.backend; starred: tab.app.starred }
    readonly property alias view: viewObj
    readonly property string path: special !== "" ? special + ":" : folderObj.path
    readonly property string title: special !== "" ? specialNames[special] : app.folderName(path || startPath)

    // ── The folder's view (FmViews through the app) ──
    property string viewMode: "list"
    property var sort: ({ by: "name", reverse: false, dirsFirst: true })
    property var iconSizes: ({ list: FmZoom.def.list, grid: FmZoom.def.grid })
    property bool ownView: false
    property bool introduced: false       // its chip in the tab strip has grown in
    readonly property int iconSize: iconSizes[viewMode]
    function _takeView(p) {
        const r = app.viewFor(p)
        viewMode = r.view
        // folders first is one setting for every folder (Settings.files.dirsFirst)
        sort = { by: r.sort.by, reverse: r.sort.reverse, dirsFirst: Settings.files.dirsFirst ?? true }
        iconSizes = { list: FmZoom.clamp("list", r.iconSize.list), grid: FmZoom.clamp("grid", r.iconSize.grid) }
        ownView = r.own
    }
    function setView(m) { viewMode = m; ownView = true; app.rememberView(path, { view: m }) }
    function setSort(s) {
        if (s.dirsFirst !== (Settings.files.dirsFirst ?? true)) Settings.set("files", "dirsFirst", s.dirsFirst)
        // search results: sorted here, nothing remembered
        if (folder === searchObj) {
            searchObj.relevance = false
            searchObj.sortBy = s.by
            searchObj.reverse = s.reverse
            sort = s
            return
        }
        sort = s; ownView = true; folderObj.setSort(s); app.rememberView(path, { sort: { by: s.by, reverse: s.reverse } })
    }
    function sortBy(by) { setSort({ by: by, reverse: sort.by === by ? !sort.reverse : false, dirsFirst: sort.dirsFirst }) }
    // the folders-first setting changed (here or in another window / the Settings app)
    readonly property bool dirsFirstSetting: Settings.files.dirsFirst ?? true
    onDirsFirstSettingChanged: if (sort.dirsFirst !== dirsFirstSetting) { sort = Object.assign({}, sort, { dirsFirst: dirsFirstSetting }); folderObj.setSort(sort) }
    function setIconSize(size) {
        const o = Object.assign({}, iconSizes)
        o[viewMode] = size
        iconSizes = o
        ownView = true
        const patch = {}
        patch[viewMode] = size
        app.rememberView(path, { iconSize: patch })
    }
    // this folder back to the defaults
    function resetView() { app.forgetView(path); _takeView(path); folderObj.setSort(sort) }
    // this folder's view for every folder without its own
    function makeDefault() { app.setViewDefaults(viewMode, sort, iconSizes); app.forgetView(path); ownView = false }

    // ── Where we are ──
    FmFolder {
        id: folderObj
        backend: tab.app.backend
        showHidden: tab.app.showHidden
        countItems: FmSettings.allowed(Settings.files.counts ?? "local", fs)
        onLoaded: {
            tab.placeCursor()
            tab._takeWanted()
            // a new folder slides in (into it: from the right, out / back: from the left)
            if (folderObj.path !== tab._shown && tab.visible) tab.view.enter(tab._way * Tokens.space.s24)
            else if (tab.view.leaving) tab.view.enter(0)      // (it didn't change after all: back to normal)
            tab._shown = folderObj.path
        }
        onNotFolder: {
            // a file was asked for: its folder, with it selected
            const p = folderObj.path
            tab.go(FmPath.parent(p), { select: FmPath.base(p), noHistory: true })
        }
        onGone: tab.go(FmPath.parent(folderObj.path), { noHistory: true })
    }

    property var history: []              // [{ path, select }] behind
    property var future: []               // ahead (after going back)
    property string pendingSelect: ""     // the item to put the cursor on once listed
    property string cursorName: ""        // the item under the cursor (kept across reloads)
    property int _way: 0                  // +1 into a folder, -1 out of it / back: where the next one slides in from
    property string _shown: ""            // the folder the view last came in on

    // ── Search (like Nautilus: typing starts it, Esc ends it) ──
    property bool searching: false
    property string query: ""
    property var searchOpts: ({ kinds: [], since: 0 })
    FmSearch { id: searchObj; backend: tab.app.backend }
    function search(q, opts) {
        searching = true
        query = q
        if (opts) searchOpts = opts
        const deep = FmSettings.allowed(Settings.files.searchDepth ?? "local", folderObj.fs)
        viewObj.clearSelection()
        searchObj.run(folderObj.path, q, { depth: deep ? 64 : 0, hidden: app.showHidden, kinds: searchOpts.kinds, since: searchOpts.since })
    }
    function endSearch() {
        if (!searching) return
        searching = false
        query = ""
        searchObj.run(folderObj.path, "", {})
        searchObj.relevance = true
        viewObj.clearSelection()
        placeCursor()
    }
    // a search result's folder, with it selected
    function openLocation(i) {
        const it = folder.at(i)
        if (it) go(FmPath.parent(folder.pathOf(it)), { select: it.name })
    }

    function go(p, opt) {
        opt = opt ?? {}
        if (searching) endSearch()
        const sp = /^([a-z]+):$/.exec(p)
        if (sp && specialNames[sp[1]]) {
            if (path !== p && path !== "" && !opt.noHistory) {
                history = history.concat([{ path: path, select: cursorName }]).slice(-100)
                future = []
            }
            special = sp[1]
            viewObj.clearSelection()
            virtualObj.load(special)
            win.tabMoved(tab)
            return
        }
        const wasSpecial = special !== ""
        if (wasSpecial) {
            if (!opt.noHistory) { history = history.concat([{ path: path, select: "" }]).slice(-100); future = [] }
            special = ""
            opt = Object.assign({}, opt, { noHistory: true })
        }
        p = FmPath.normalize(p)
        const from = folderObj.path
        if (wasSpecial && p === from) { viewObj.clearSelection(); placeCursor(); win.tabMoved(tab); return }
        if (p === from && !opt.force) { if (opt.select) selectName(opt.select); return }
        if (from !== "" && !opt.noHistory) {
            history = history.concat([{ path: from, select: cursorName }]).slice(-100)
            future = []
        }
        // going up: the folder we came out of gets the cursor
        pendingSelect = opt.select ?? (from !== "" && FmPath.under(from, p) && from !== p ? from.slice(p === "/" ? 1 : p.length + 1).split("/")[0] : "")
        _way = from === "" ? 0 : FmPath.under(p, from) ? 1 : (FmPath.under(from, p) || opt.noHistory) ? -1 : 1
        cursorName = ""
        viewObj.clearSelection()
        _takeView(p)
        view.leave(_way * Tokens.space.s24)
        folderObj.load(p, sort)
        win.tabMoved(tab)
    }
    function back() {
        if (history.length === 0) return
        _way = -1
        const h = history[history.length - 1]
        history = history.slice(0, -1)
        future = future.concat([{ path: path, select: cursorName }])
        go(h.path, { select: h.select, noHistory: true })
    }
    function forward() {
        if (future.length === 0) return
        const f = future[future.length - 1]
        future = future.slice(0, -1)
        history = history.concat([{ path: path, select: cursorName }])
        go(f.path, { select: f.select, noHistory: true })
    }
    function up() { if (special === "" && folderObj.path !== "/") go(FmPath.parent(folderObj.path)) }

    // a listing is in: the item asked for gets the cursor and the selection;
    // a reload of the same folder keeps both (the selection is kept by name)
    function placeCursor() {
        if (pendingSelect) {
            selectName(pendingSelect)
            pendingSelect = ""
            return
        }
        viewObj.setCurrent(cursorName ? folderObj.indexOf(cursorName) : -1)
    }
    function selectName(name) {
        const i = folderObj.indexOf(name)
        viewObj.setCurrent(i)
        viewObj.selectOnly(i)
    }
    Connections {
        target: viewObj
        function onCurrentIndexChanged() {
            // a listing being refilled moves the cursor through -1: keep the name then
            if (folderObj.loading || tab.folder !== folderObj) return
            tab.cursorName = viewObj.currentIndex >= 0 ? (folderObj.at(viewObj.currentIndex)?.name ?? "") : ""
        }
    }

    // double-click / Enter on row i: with several selected (i among them) every
    // selected file opens in its app and every folder in a tab of its own; one folder alone is entered
    function activate(i) {
        const it = folder.at(i)
        if (!it) return
        const sel = viewObj.selection[it.key] ? viewObj.selectedItems() : [it]
        if (sel.length === 1) { open(folder.indexOf(sel[0].key)); return }
        const files = sel.filter(x => !x.dir && !x.broken), dirs = sel.filter(x => x.dir)
        if (files.length + dirs.length > 10) { win.toast("That's " + sel.length + " items — select at most 10 to open them all"); return }
        for (const d of dirs) win.newTab(folder.pathOf(d), { background: true })
        for (const f of files) app.backend.request("launch", { path: folder.pathOf(f) }, { error: msg => tab.win.toast(msg) })
    }
    function open(i) {
        const it = folder.at(i)
        if (!it) return
        // the network: a server or a share — connect, then its folder
        if (special === "network") { app.ops.connect(it.uri, res => tab.go(res.path)); return }
        if (special === "trash") { win.toast("“" + FmFormat.shown(it.name) + "” is in the trash — restore it first (right-click)", "info"); return }
        const p = folder.pathOf(it)
        if (it.dir) { go(p); return }
        if (it.broken) { win.toast("“" + FmFormat.shown(it.name) + "” is a link to something that doesn't exist (" + it.target + ")"); return }
        // programs, scripts and launchers ask first (the window's openFile)
        win.openFile(p, it)
    }
    // middle click, like Nautilus: a folder opens in a new tab behind this one, a file in its app
    function openAside(i) {
        const it = folder.at(i)
        if (!it) return
        if (it.dir) win.newTab(folder.pathOf(it), { background: true })
        else open(i)
    }

    // what an operation made here gets selected as it arrives (live changes come a moment later)
    property var _want: ({})
    function selectSoon(names) {
        const w = {}
        for (const n of names) w[n] = true
        _want = w
        wantTimer.restart()
        _takeWanted()
    }
    function _takeWanted() {
        const names = Object.keys(_want)
        if (names.length === 0) return
        const sel = {}
        let first = -1
        for (const n of names) {
            const i = folderObj.indexOf(n)
            if (i < 0) continue
            sel[n] = true
            if (first < 0 || i < first) first = i
        }
        if (first < 0) return
        viewObj.selection = sel
        viewObj.anchor = folderObj.at(first).name
        viewObj.setCurrent(first)
    }
    Timer { id: wantTimer; interval: 3000; onTriggered: tab._want = ({}) }
    Connections {
        target: folderObj
        function onChanged() { tab._takeWanted() }
    }

    function info() {
        return { path: path, special: special, searching: searching, query: query, results: searching ? searchObj.count : 0, count: folderObj.count, hiddenCount: folderObj.hiddenCount,
                 loading: folderObj.loading, error: folderObj.error, current: cursorName, view: viewMode,
                 selected: Object.keys(viewObj.selection).slice(0, 50), iconSize: iconSize, ownView: ownView,
                 hidden: app.showHidden, sort: sort, columns: app.columns, back: history.length, forward: future.length }
    }

    FolderView {
        id: viewObj
        anchors.fill: parent
        folder: tab.folder
        singleClick: (Settings.files.click ?? "double") === "single"
        caption: Settings.files.captions ?? "none"
        themed: Settings.files.iconTheme ?? false
        thumbFor: FmSettings.allowed(Settings.files.thumbs ?? "local", folderObj.fs) ? tab.app.thumbs.get : null
        thumbVersion: tab.app.thumbs.version
        mode: tab.viewMode
        iconSize: tab.iconSize
        sortBy: tab.sort.by
        reverse: tab.sort.reverse
        columns: tab.app.columns
        zoomKeys: tab.visible && tab.win.zoomKeys
        onActivated: i => tab.activate(i)
        onMiddleClicked: i => tab.openAside(i)
        onSortRequested: by => tab.sortBy(by)
        onZoomRequested: size => tab.setIconSize(size)
        onContextRequested: (i, item, x, y) => tab.win.itemMenu(tab, i, item, x, y)
        cut: tab.app.ops.cut
        onDropRequested: (drop, dir) => tab.win.handleDrop(drop, dir || folderObj.path)
        onDragStarted: paths => tab.app.dragging = paths
        onSwiped: dir => dir < 0 ? tab.back() : tab.forward()
        onSpringOpen: p => tab.go(p)
        onDragEnded: {
            tab.app.dragging = []
            // shown only to keep the drag alive (a spring-loaded tab switch): hidden again
            if (tab.win.tab !== tab) tab.visible = false
        }
        onColumnMenuRequested: (id, item, x, y) => tab.win.columnMenu(id, item, x, y)
    }

    Component.onCompleted: go(startPath || app.home, { select: startSelect, noHistory: true })
}
