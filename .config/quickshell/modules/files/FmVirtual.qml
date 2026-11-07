import QtQuick
import "lib/FmSort.js" as FmSort

// A view that isn't a folder, shaped like FmFolder for the views (model, at,
// indexOf, pathOf, count, loading, error, signals loaded / changed):
//   recent:   GTK's recently-used.xbel (newest first)
//   starred:  the starred paths (FilesApp.starred), as they are now
//   trash:    every trash folder; `orig` / `deleted` per item, `loc` = where it was
//   network:  what GVfs sees on the network (items carry `uri`; opening one connects)
// An item's `key` is its path (its URI on the network).
//   load(kind) · reload()
Item {
    id: root

    required property var backend
    property var starred: []              // paths (FilesApp.starred)
    property string kind: ""
    readonly property string path: kind + ":"
    readonly property bool showHidden: true
    readonly property bool live: false
    readonly property string fs: ""
    readonly property bool canWrite: false
    readonly property real free: -1
    readonly property var counts: ({})
    readonly property int hiddenCount: 0

    readonly property alias model: list
    property bool loading: false
    property string error: ""
    property string errorCode: ""
    property int count: 0
    property string sortBy: "name"
    property bool reverse: false
    property bool dirsFirst: true
    signal loaded()
    signal changed()

    ListModel { id: list }
    property var _items: []
    property int _gen: 0

    function at(i) { return _items[i] }
    function indexOf(key) { return _items.findIndex(r => r.key === key) }
    function pathOf(it) { return it.path }
    function setSort(s) { sortBy = s.by; reverse = s.reverse; dirsFirst = s.dirsFirst; _fill(_items) }

    function _norm(r) {
        return { name: r.name, key: r.path || r.uri, path: r.path ?? "", uri: r.uri ?? "", loc: r.loc ?? "",
                 dir: !!r.dir, size: r.size ?? 0, mtime: r.mtime ?? 0, type: r.type ?? "", hidden: false, link: !!r.link,
                 mode: r.mode ?? 0, exec: !!r.exec, ro: !!r.ro, owner: r.owner ?? "", group: r.group ?? "", target: r.target ?? "", broken: !!r.broken,
                 orig: r.orig ?? "", info: r.info ?? "", deleted: r.deleted ?? "", icon: r.icon ?? "" }
    }
    function _fill(items) {
        // recent: newest first (as they come); the rest: like a folder
        if (kind !== "recent") items.sort((a, b) => FmSort.compare(a, b, { by: sortBy, reverse: reverse, dirsFirst: dirsFirst }))
        _items = items
        list.clear()
        for (let i = 0; i < items.length; i += 1000) list.append(items.slice(i, i + 1000))
        count = items.length
    }

    function load(k) { kind = k; reload() }
    function reload() {
        const gen = ++_gen
        loading = true
        error = ""
        errorCode = ""
        const cb = {
            done: res => {
                if (gen !== root._gen) return
                root.loading = false
                root._fill((res.items ?? []).filter(x => x).map(root._norm))
                root.loaded()
            },
            error: (msg, code) => {
                if (gen !== root._gen) return
                root.loading = false
                root.error = msg
                root.errorCode = code
                root._fill([])
                root.loaded()
            }
        }
        if (kind === "recent") backend.request("recent", {}, cb)
        else if (kind === "trash") backend.request("trashList", {}, cb)
        else if (kind === "network") backend.request("network", {}, cb)
        else if (kind === "starred") {
            if (starred.length === 0) { cb.done({ items: [] }); return }
            backend.request("info", { paths: starred.slice(0, 1000) }, {
                done: res => cb.done({ items: res.items.map((it, i) => it ? Object.assign(it, { path: root.starred[i],
                                                                                               loc: root.starred[i].replace(/\/[^/]*$/, "") || "/" }) : null) }),
                error: cb.error
            })
        }
    }
    // a star added / taken away while it's shown
    onStarredChanged: if (kind === "starred") reload()
}
