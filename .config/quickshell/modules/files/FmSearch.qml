import QtQuick
import "lib/FmSort.js" as FmSort

// A search's results, shaped like FmFolder for the views (model, at, indexOf,
// pathOf, count, loading, error, signals loaded / changed): the backend's
// "search" streams them in; best match first (relevance) unless sorted by a
// column. An item's `key` is its path (names repeat across folders), `loc`
// the folder it's in, relative to the searched one.
//
//   run(base, query, { depth, hidden, kinds, since })   stop()
//   relevance: sorted by match (true) or by sortBy / reverse / dirsFirst
Item {
    id: root

    required property var backend
    property string path: ""              // the folder searched in
    property string query: ""
    property bool relevance: true
    property string sortBy: "name"
    property bool reverse: false
    property bool dirsFirst: true
    readonly property bool showHidden: true
    readonly property bool live: false

    readonly property alias model: list
    property bool loading: false
    property bool more: false             // stopped at the limit
    property string error: ""
    property string errorCode: ""
    property int count: 0
    readonly property int hiddenCount: 0
    property bool canWrite: true
    property string fs: ""
    readonly property real free: -1
    readonly property var counts: ({})
    signal loaded()
    signal changed()

    ListModel { id: list }
    property var _items: []
    property int _id: 0

    function at(i) { return _items[i] }
    function indexOf(key) { return _items.findIndex(r => r.key === key) }
    function pathOf(it) { return it.path }

    function _order(a, b) {
        if (relevance) return (b.score - a.score) || FmSort.compare(a, b, { by: "name", dirsFirst: false })
        return FmSort.compare(a, b, { by: sortBy, reverse: reverse, dirsFirst: dirsFirst })
    }
    function _refill() {
        _items.sort(_order)
        list.clear()
        for (let i = 0; i < _items.length; i += 1000) list.append(_items.slice(i, i + 1000))
        count = _items.length
    }
    onRelevanceChanged: _refill()
    onSortByChanged: if (!relevance) _refill()
    onReverseChanged: if (!relevance) _refill()

    function _norm(r) {
        return { name: r.name, key: r.path, path: r.path, loc: r.loc ?? "", score: r.score ?? 0, dir: !!r.dir,
                 size: r.size ?? 0, mtime: r.mtime ?? 0, type: r.type ?? "", hidden: !!r.hidden, link: !!r.link,
                 mode: r.mode ?? 0, exec: !!r.exec, ro: !!r.ro, owner: r.owner ?? "", group: r.group ?? "", target: r.target ?? "", broken: !!r.broken }
    }

    function stop() {
        if (_id) backend.cancel(_id)
        _id = 0
        loading = false
    }
    function run(base, q, opts) {
        stop()
        path = base
        query = q
        error = ""
        errorCode = ""
        more = false
        _items = []
        list.clear()
        count = 0
        if (q.trim() === "") { loaded(); return }
        loading = true
        let id = 0
        id = backend.request("search", Object.assign({ path: base, query: q }, opts ?? {}), {
            // batches go in at once (the first matches show while it goes on), sorted when it ends
            batch: items => {
                if (id !== root._id) return
                const add = items.map(root._norm)
                root._items = root._items.concat(add)
                list.append(add)
                root.count = root._items.length
                root.changed()
            },
            done: res => {
                if (id !== root._id) return
                root._id = 0
                root.loading = false
                root.more = res.more === true
                root._refill()
                root.loaded()
            },
            error: (msg, code) => {
                if (id !== root._id || code === "cancelled") return
                root._id = 0
                root.loading = false
                root.error = msg
                root.errorCode = code
                root.loaded()
            }
        })
        _id = id
    }

    Component.onDestruction: stop()
}
