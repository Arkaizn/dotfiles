.pragma library

// The list view's columns besides the name: which ones, in which order (the
// state's `columns`), and which of them fit. Widths are in rows (Tokens.size.row).
//   all                     [{ id, label, width, sort?, right?, searchOnly? }]   sort: the backend's sort key
//                           (loc: where a search result is — only in search results, never chosen)
//   chosen(raw)             a checked list of ids (unknown / doubled dropped); default: size, mtime, type
//   fit(ids, width, row)    { id: px } for the columns that fit, in order; the last ones give way first
//   toggle(ids, id) · move(ids, id, dir)   new lists (dir -1 left, +1 right)
//   perms(mode)             "rwxr-xr-x" (a leading "d" / "l" isn't added: the icon says that)

var all = [
    { id: "size", label: "Size", width: 2, sort: "size", right: true },
    { id: "mtime", label: "Modified", width: 3, sort: "mtime" },
    { id: "type", label: "Type", width: 3.5, sort: "type" },
    { id: "perms", label: "Permissions", width: 2.5 },
    { id: "owner", label: "Owner", width: 2 },
    { id: "group", label: "Group", width: 2 },
    { id: "loc", label: "Location", width: 4, searchOnly: true }
]
var def = ["size", "mtime", "type"]
// the name column keeps at least this many rows of room
var nameMin = 4

function spec(id) {
    for (let i = 0; i < all.length; i++) if (all[i].id === id) return all[i]
    return null
}

function chosen(raw) {
    if (!Array.isArray(raw)) return def.slice()
    const out = []
    for (const id of raw) if (spec(id) && !spec(id).searchOnly && out.indexOf(id) < 0) out.push(id)
    return out
}

function fit(ids, width, row) {
    let room = width - nameMin * row
    const out = {}
    for (const id of ids) {
        const w = spec(id).width * row
        if (w > room) break
        out[id] = w
        room -= w
    }
    return out
}

function toggle(ids, id) {
    if (!spec(id) || spec(id).searchOnly) return ids.slice()
    return ids.indexOf(id) >= 0 ? ids.filter(x => x !== id) : ids.concat([id])
}

function move(ids, id, dir) {
    const i = ids.indexOf(id), j = i + (dir < 0 ? -1 : 1)
    if (i < 0 || j < 0 || j >= ids.length) return ids.slice()
    const out = ids.slice()
    out[i] = out[j]
    out[j] = id
    return out
}

function perms(mode) {
    const m = Number(mode) || 0
    let s = ""
    for (let shift = 6; shift >= 0; shift -= 3) {
        const b = (m >> shift) & 7
        s += (b & 4 ? "r" : "-") + (b & 2 ? "w" : "-") + (b & 1 ? "x" : "-")
    }
    // setuid / setgid / sticky in the x places, like ls
    const c = s.split("")
    if (m & 0o4000) c[2] = c[2] === "x" ? "s" : "S"
    if (m & 0o2000) c[5] = c[5] === "x" ? "s" : "S"
    if (m & 0o1000) c[8] = c[8] === "x" ? "t" : "T"
    return c.join("")
}
