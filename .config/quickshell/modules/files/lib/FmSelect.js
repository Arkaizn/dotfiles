.pragma library

// Which items are selected, like Nautilus: a set of names (they survive a
// re-sort, a reload and live changes) plus the anchor a Shift range starts from.
//   click(state, i, mods, nameAt)   a click on row i → new state
//       plain: only it · Ctrl: toggle it · Shift: anchor…i · Ctrl+Shift: anchor…i added
//   moveTo(state, i, extend, nameAt)  the cursor moved there by a key (Shift: extend)
//   all(count, nameAt) · prune(state, present)  (drop names that are gone)
//   invert(sel, count, nameAt)
//   glob(pattern)  a RegExp for "*.png", "IMG_??.jpg", "*.{jpg,png}", "[ab]*" (whole name,
//                  ignoring case); several patterns separated by ";" · null when empty
//   matching(count, nameAt, re)  the names it matches
//   band(r, geo, count)  the rows a rubber band covers: r { x1, y1, x2, y2 } in content
//                  coordinates; geo { rowH } (list) or { cellW, cellH, cols } (grid)
// state: { sel: { name: true }, anchor: name }; nameAt(i) gives row i's name.
// mods: Qt.ControlModifier = 0x04000000, Qt.ShiftModifier = 0x02000000

var CTRL = 0x04000000, SHIFT = 0x02000000

function only(name) {
    const sel = {}
    if (name !== "") sel[name] = true
    return { sel: sel, anchor: name }
}

function range(a, b, nameAt, base) {
    const sel = Object.assign({}, base || {})
    for (let i = Math.min(a, b); i <= Math.max(a, b); i++) sel[nameAt(i)] = true
    return sel
}

function anchorIndex(state, count, nameAt, fallback) {
    for (let i = 0; i < count; i++) if (nameAt(i) === state.anchor) return i
    return fallback
}

function click(state, i, mods, nameAt, count) {
    const name = nameAt(i)
    if (mods & SHIFT) {
        const a = anchorIndex(state, count, nameAt, i)
        return { sel: range(a, i, nameAt, mods & CTRL ? state.sel : null), anchor: state.anchor || name }
    }
    if (mods & CTRL) {
        const sel = Object.assign({}, state.sel)
        if (sel[name]) delete sel[name]
        else sel[name] = true
        return { sel: sel, anchor: name }
    }
    return only(name)
}

function moveTo(state, i, extend, nameAt, count) {
    if (!extend) return only(nameAt(i))
    const a = anchorIndex(state, count, nameAt, i)
    return { sel: range(a, i, nameAt, null), anchor: state.anchor || nameAt(i) }
}

function all(count, nameAt) {
    const sel = {}
    for (let i = 0; i < count; i++) sel[nameAt(i)] = true
    return sel
}

function prune(state, present) {
    const sel = {}
    let changed = false
    for (const n in state.sel) {
        if (present[n]) sel[n] = true
        else changed = true
    }
    return changed ? { sel: sel, anchor: present[state.anchor] ? state.anchor : "" } : state
}

function invert(sel, count, nameAt) {
    const out = {}
    for (let i = 0; i < count; i++) { const n = nameAt(i); if (!sel[n]) out[n] = true }
    return out
}

function glob(pattern) {
    const parts = String(pattern).split(";").map(p => p.trim()).filter(p => p !== "")
    if (parts.length === 0) return null
    const one = p => {
        let re = "", depth = 0
        for (let i = 0; i < p.length; i++) {
            const c = p[i]
            // [^] rather than ".": a name may hold a newline
            if (c === "*") re += "[^]*"
            else if (c === "?") re += "[^]"
            else if (c === "[") {
                const end = p.indexOf("]", i + 2)
                if (end < 0) { re += "\\["; continue }
                let body = p.slice(i + 1, end).replace(/\\/g, "\\\\")
                if (body[0] === "!") body = "^" + body.slice(1)
                re += "[" + body.replace(/^\^?\]/, m => m.replace("]", "\\]")) + "]"
                i = end
            } else if (c === "{") { re += "(?:"; depth++ }
            else if (c === "}" && depth > 0) { re += ")"; depth-- }
            else if (c === "," && depth > 0) re += "|"
            else re += c.replace(/[.+^$()|\\\/\]\}]/g, "\\$&")
        }
        while (depth-- > 0) re += ")"
        return re
    }
    try { return new RegExp("^(?:" + parts.map(one).join("|") + ")$", "i") } catch (e) { return null }
}

function matching(count, nameAt, re) {
    const out = {}
    if (!re) return out
    for (let i = 0; i < count; i++) { const n = nameAt(i); if (re.test(n)) out[n] = true }
    return out
}

function band(r, geo, count) {
    const top = Math.max(0, Math.min(r.y1, r.y2)), bottom = Math.max(r.y1, r.y2)
    const out = []
    if (count === 0) return out
    if (geo.cols === undefined) {
        const a = Math.floor(top / geo.rowH), b = Math.min(count - 1, Math.floor(bottom / geo.rowH))
        for (let i = a; i <= b; i++) out.push(i)
        return out
    }
    const left = Math.max(0, Math.min(r.x1, r.x2)), right = Math.max(r.x1, r.x2)
    const c0 = Math.floor(left / geo.cellW), c1 = Math.min(geo.cols - 1, Math.floor(right / geo.cellW))
    const r0 = Math.floor(top / geo.cellH), r1 = Math.floor(bottom / geo.cellH)
    for (let row = r0; row <= r1; row++)
        for (let c = c0; c <= c1; c++) {
            const i = row * geo.cols + c
            if (i < count) out.push(i)
        }
    return out
}
