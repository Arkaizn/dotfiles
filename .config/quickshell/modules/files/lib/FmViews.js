.pragma library

// What the file manager remembers about views and windows (FmState, version 2).
// Per-folder view memory: a folder you changed the view / sort / icon size of
// keeps it; every other folder shows the defaults (the state's own view / sort
// / iconSize). Only what was changed is stored, so a later default still
// reaches the rest of a folder's options. At most CAP folders, the oldest go.
//   sortOf(raw, def)                     a checked { by, reverse, dirsFirst }
//   resolve(folders, path, defaults)     { view, sort, iconSize: { list, grid }, own }   own: anything remembered
//   remember(folders, path, patch, now)  new folders map; patch: { view?, sort?, iconSize?: { list?, grid? } }
//   forget(folders, path)                new folders map without it
//   windows(raw)                         [{ tabs: [{ path }], active, width?, height? }] (v1's [{ path }] too)
// Icon sizes are kept as given; the caller clamps them to FmZoom's steps.

var CAP = 500
var VIEWS = ["list", "grid"]
var SORTS = ["name", "size", "mtime", "type"]

function obj(o) { return o !== null && typeof o === "object" && !Array.isArray(o) ? o : {} }
function num(v) { return typeof v === "number" && isFinite(v) && v > 0 ? v : undefined }

function sortOf(raw, def) {
    const s = obj(raw), d = def || { by: "name", reverse: false, dirsFirst: true }
    return { by: SORTS.indexOf(s.by) >= 0 ? s.by : d.by,
             reverse: typeof s.reverse === "boolean" ? s.reverse : d.reverse,
             dirsFirst: typeof s.dirsFirst === "boolean" ? s.dirsFirst : d.dirsFirst }
}

function resolve(folders, path, defaults) {
    const f = obj(obj(folders)[path]), d = defaults
    const sizes = obj(f.iconSize)
    return {
        view: VIEWS.indexOf(f.view) >= 0 ? f.view : d.view,
        sort: f.sort !== undefined ? sortOf(f.sort, d.sort) : d.sort,
        iconSize: { list: num(sizes.list) ?? d.iconSize.list, grid: num(sizes.grid) ?? d.iconSize.grid },
        own: f.view !== undefined || f.sort !== undefined || f.iconSize !== undefined
    }
}

function remember(folders, path, patch, now) {
    const all = Object.assign({}, obj(folders))
    const f = Object.assign({}, obj(all[path]))
    if (patch.view !== undefined) f.view = patch.view
    if (patch.sort !== undefined) f.sort = patch.sort
    if (patch.iconSize !== undefined) f.iconSize = Object.assign({}, obj(f.iconSize), patch.iconSize)
    f.t = now
    all[path] = f
    const keys = Object.keys(all)
    if (keys.length > CAP) {
        keys.sort((a, b) => (obj(all[a]).t || 0) - (obj(all[b]).t || 0))
        for (let i = 0; i < keys.length - CAP; i++) delete all[keys[i]]
    }
    return all
}

function forget(folders, path) {
    const all = Object.assign({}, obj(folders))
    delete all[path]
    return all
}

function windows(raw) {
    if (!Array.isArray(raw)) return []
    const out = []
    for (const w of raw.slice(0, 20)) {
        const o = obj(w)
        // version 1: one tab per window, { path }
        const tabs = (Array.isArray(o.tabs) ? o.tabs : typeof o.path === "string" ? [{ path: o.path }] : [])
            // a folder, or a view like "trash:" / "recent:"
            .filter(t => typeof obj(t).path === "string" && (t.path.startsWith("/") ? t.path.indexOf("\0") < 0 : /^[a-z]+:$/.test(t.path)))
            .slice(0, 50)
            .map(t => ({ path: t.path }))
        if (tabs.length === 0) continue
        const a = typeof o.active === "number" && o.active >= 0 && o.active < tabs.length ? Math.floor(o.active) : 0
        const r = { tabs: tabs, active: a }
        if (num(o.width) && num(o.height)) { r.width = Math.round(o.width); r.height = Math.round(o.height) }
        out.push(r)
    }
    return out
}
