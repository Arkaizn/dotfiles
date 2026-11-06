import QtQuick
import "lib/FmSort.js" as FmSort
import "lib/FmPath.js" as FmPath

// One open folder: its items, sorted and kept live (the backend's file
// monitor), and how loading went. The window's views show `model`.
//
//   load(path, sort?)     list it and watch it; forgets the one before
//                         (sort { by, reverse, dirsFirst }: that folder's own order, set first)
//   setSort(sort)         another order: lists again when it changed
//   reload()              list again (a rescan, F5)
//   indexOf(name)         its row in `model`, -1 if not shown
//   at(i)                 the item of a row (a plain object; `key` = its name — FmSearch's are paths)
//   pathOf(item)          its full path
//   counts                { folder name: items in it } (countItems: asked after each listing)
//   path · loading · error ("" or the message) · errorCode · count · hiddenCount
//   canWrite · fs (its file system type: name rules) · free / size (bytes of its drive, -1 = unknown)
//   sortBy · reverse · dirsFirst   (through load / setSort) · showHidden (filters here)
//   signal loaded()       a listing is complete (the window puts the cursor)
//   signal changed()      live changes came in
//   signal gone()         the folder itself was deleted or unmounted
//   signal notFolder()    the path is a file (the window opens its folder and selects it)
//
// Hidden items are always listed and filtered here, so Ctrl+H needs no new listing.
Item {
    id: root

    required property var backend
    property string path: ""
    property string sortBy: "name"
    property bool reverse: false
    property bool dirsFirst: true
    property bool showHidden: false
    property bool countItems: false
    property var counts: ({})

    readonly property alias model: list
    property bool loading: false
    property string error: ""
    property string errorCode: ""
    property int count: 0
    property int hiddenCount: 0
    property bool canWrite: true
    property string fs: ""
    property real free: -1
    property real size: -1
    // true while live changes are put in (the views animate those, not whole listings)
    property bool live: false
    signal loaded()
    signal changed()
    signal gone()
    signal notFolder()

    // every item (hidden ones too), sorted; `shown` is what the model holds, same order
    property var _all: []
    property var _shown: []
    property int _gen: 0
    property int _listId: 0
    property int _watch: 0
    property var _early: []           // changes that came while the listing was still running

    readonly property var opts: ({ by: sortBy, reverse: reverse, dirsFirst: dirsFirst })
    function _takeSort(s) {
        if (!s) return false
        const same = s.by === sortBy && s.reverse === reverse && s.dirsFirst === dirsFirst
        sortBy = s.by
        reverse = s.reverse
        dirsFirst = s.dirsFirst
        return !same
    }
    function setSort(s) { if (_takeSort(s) && path !== "") reload() }
    onShowHiddenChanged: _refill()

    ListModel { id: list }

    function at(i) { return _shown[i] }
    function pathOf(it) { return FmPath.join(path, it.name) }
    function indexOf(name) { return _shown.findIndex(r => r.name === name) }

    function load(p, s) {
        _takeSort(s)
        _stop()
        path = p
        error = ""
        errorCode = ""
        free = -1
        size = -1
        const gen = ++_gen
        // the watch first: nothing that changes while it's listed gets lost
        backend.request("watch", { path: p }, {
            done: res => { if (gen === root._gen) root._watch = res.watch; else root.backend.request("unwatch", { watch: res.watch }) },
            error: () => {}
        })
        _list(gen)
        backend.request("free", { path: p }, {
            done: res => { if (gen === root._gen) { root.free = res.free; root.size = res.size } },
            error: () => {}
        })
    }

    function reload() {
        if (_listId) backend.cancel(_listId)
        _list(_gen)
    }

    function _list(gen) {
        loading = true
        let fresh = []
        _early = []
        _listId = backend.request("list", { path: path, hidden: true, sort: sortBy, reverse: reverse, dirsFirst: dirsFirst }, {
            batch: items => { if (gen === root._gen) fresh = fresh.concat(items.map(root._norm)) },
            done: res => {
                if (gen !== root._gen) return
                root._listId = 0
                root.canWrite = res.canWrite
                root.fs = res.fs ?? ""
                root._all = fresh
                root._refill()
                root.loading = false
                root._count(gen, root._all.filter(r => r.dir).map(r => r.name))
                const early = root._early
                root._early = []
                for (const m of early) root._apply(m)
                root.loaded()
            },
            error: (msg, code) => {
                if (gen !== root._gen || code === "cancelled") return
                root._listId = 0
                root.loading = false
                if (code === "notdir") { root.notFolder(); return }
                root._all = []
                root._refill()
                root.error = msg
                root.errorCode = code
                root.loaded()
            }
        })
    }

    // how many items each subfolder holds (the size column), in chunks; `more`: a live
    // change adds to what's there, a listing starts over
    function _count(gen, names, more) {
        if (!more) counts = ({})
        if (!countItems || names.length === 0) return
        for (let i = 0; i < names.length; i += 2000) {
            backend.request("counts", { dir: path, names: names.slice(i, i + 2000), hidden: showHidden }, {
                done: res => { if (gen === root._gen) root.counts = Object.assign({}, root.counts, res.counts) },
                error: () => {}
            })
        }
    }

    function _stop() {
        if (_listId) backend.cancel(_listId)
        _listId = 0
        if (_watch) backend.request("unwatch", { watch: _watch })
        _watch = 0
    }

    // one shape for every item: a ListModel fixes its roles' types from the first row
    function _norm(r) {
        return { name: r.name, key: r.name, dir: !!r.dir, size: r.size ?? 0, mtime: r.mtime ?? 0, type: r.type ?? "",
                 hidden: !!r.hidden, link: !!r.link, mode: r.mode ?? 0, exec: !!r.exec, ro: !!r.ro, owner: r.owner ?? "", group: r.group ?? "",
                 target: r.target ?? "", broken: !!r.broken, loc: "" }
    }

    function _refill() {
        const shown = showHidden ? _all.slice() : _all.filter(r => !r.hidden)
        _shown = shown
        list.clear()
        for (let i = 0; i < shown.length; i += 2000) list.append(shown.slice(i, i + 2000))
        count = shown.length
        hiddenCount = _all.length - _all.filter(r => !r.hidden).length
    }

    Connections {
        target: root.backend
        function onEvent(m) {
            if (m.watch === undefined || m.watch !== root._watch) return
            if (root.loading) { root._early.push(m); return }
            root._apply(m)
        }
        // the backend came back after a crash: its watches are gone
        function onRestarted() { if (root.path !== "") root.load(root.path) }
    }

    function _apply(m) {
        if (m.event === "gone") { root.gone(); return }
        if (m.rescan) { reload(); return }
        live = true
        Qt.callLater(() => root.live = false)
        for (const c of m.changes ?? []) {
            const name = c.kind === "upsert" ? c.item.name : c.name
            _remove(name)
            if (c.kind === "upsert") {
                _insert(_norm(c.item))
                if (c.item.dir) _count(_gen, [c.item.name], true)
            }
        }
        count = _shown.length
        hiddenCount = _all.filter(r => r.hidden).length
        changed()
    }

    function _remove(name) {
        const a = _all.findIndex(r => r.name === name)
        if (a >= 0) _all.splice(a, 1)
        const s = _shown.findIndex(r => r.name === name)
        if (s >= 0) { _shown.splice(s, 1); list.remove(s) }
    }

    function _insert(item) {
        _all.splice(FmSort.insertIndex(_all.length, i => _all[i], item, opts), 0, item)
        if (item.hidden && !showHidden) return
        const s = FmSort.insertIndex(_shown.length, i => _shown[i], item, opts)
        _shown.splice(s, 0, item)
        list.insert(s, item)
    }

    Component.onDestruction: _stop()
}
