.pragma library

// The order of a folder's items. Must match scripts/files/filesd/listing.py
// (sort_items): the backend sorts the listing, this places live changes into
// it. Natural and case-insensitive ("file2" before "file10"), ties by the exact
// name; folders first (also when reversed) unless dirsFirst is off.
//   compare(a, b, { by: "name" | "size" | "mtime" | "type", reverse, dirsFirst })
//   insertIndex(count, at, item, opts)   where item goes; at(i) reads the sorted list

function chunks(name) {
    return String(name).toLowerCase().split(/([0-9]+)/)
}

function raw(a, b) { return a < b ? -1 : a > b ? 1 : 0 }

function nameCmp(a, b) {
    const x = chunks(a), y = chunks(b)
    const n = Math.min(x.length, y.length)
    for (let i = 0; i < n; i++) {
        let c
        if (i % 2) {
            // a number: by value (length without leading zeros, then digits), never parseInt
            const p = x[i].replace(/^0+/, "") || "0", q = y[i].replace(/^0+/, "") || "0"
            c = p.length - q.length || raw(p, q)
        } else {
            c = raw(x[i], y[i])
        }
        if (c !== 0) return c
    }
    return x.length - y.length || raw(a, b)
}

function compare(a, b, opts) {
    const o = opts || {}
    if (o.dirsFirst !== false && a.dir !== b.dir) return a.dir ? -1 : 1
    let c = 0
    if (o.by === "size") c = a.size - b.size
    else if (o.by === "mtime") c = a.mtime - b.mtime
    else if (o.by === "type") c = raw(a.type, b.type)
    if (c === 0) c = nameCmp(a.name, b.name)
    return o.reverse ? -c : c
}

function insertIndex(count, at, item, opts) {
    let lo = 0, hi = count
    while (lo < hi) {
        const mid = (lo + hi) >> 1
        if (compare(at(mid), item, opts) <= 0) lo = mid + 1
        else hi = mid
    }
    return lo
}
