.pragma library

// Panels on any screen edge (Part 6.6). Everything that hangs from the bar or
// a screen edge is laid out once in "canonical" coordinates — as if it hung
// down from a bar at the top:
//   u: along the edge (left → right of a top bar)
//   v: away from the edge, into the screen (0 = the edge / bar side)
// and mapped to the real surface for the edge it's on. Outlines (Shapes) get
// the whole map as a matrix; content is only moved (mapRect), never rotated.
// D = the surface's size away from the edge (its depth).

function vertical(edge) { return edge === "left" || edge === "right" }

// canonical point → surface point
function mapPoint(edge, D, u, v) {
    switch (edge) {
    case "bottom": return { x: u, y: D - v }
    case "left":   return { x: v, y: u }
    case "right":  return { x: D - v, y: u }
    default:       return { x: u, y: v }
    }
}

// canonical rectangle (u, v, along length w, depth h) → surface rectangle
function mapRect(edge, D, u, v, w, h) {
    switch (edge) {
    case "bottom": return { x: u, y: D - v - h, w: w, h: h }
    case "left":   return { x: v, y: u, w: h, h: w }
    case "right":  return { x: D - v - h, y: u, w: h, h: w }
    default:       return { x: u, y: v, w: w, h: h }
    }
}

// the same as a row-major 4×4 matrix (Qt.matrix4x4(...m)), for an item that
// is laid out canonically from the surface's origin
function matrix(edge, D) {
    switch (edge) {
    case "bottom": return [1, 0, 0, 0,  0, -1, 0, D,  0, 0, 1, 0,  0, 0, 0, 1]
    case "left":   return [0, 1, 0, 0,  1, 0, 0, 0,   0, 0, 1, 0,  0, 0, 0, 1]
    case "right":  return [0, -1, 0, D, 1, 0, 0, 0,   0, 0, 1, 0,  0, 0, 0, 1]
    default:       return [1, 0, 0, 0,  0, 1, 0, 0,   0, 0, 1, 0,  0, 0, 0, 1]
    }
}

// screen size along / across an edge
function along(edge, sw, sh) { return vertical(edge) ? sh : sw }
function across(edge, sw, sh) { return vertical(edge) ? sw : sh }

// the screen edge opposite `edge`
function opposite(edge) {
    return { top: "bottom", bottom: "top", left: "right", right: "left" }[edge] ?? "bottom"
}

// a panel's size (screen width / height) as along / depth for an edge
function toCanon(edge, w, h) { return vertical(edge) ? { along: h, depth: w } : { along: w, depth: h } }

// layer-shell anchors of a surface spanning the whole edge
function anchors(edge) {
    const v = vertical(edge)
    return { top: edge === "top" || v, bottom: edge === "bottom" || v,
             left: edge === "left" || !v, right: edge === "right" || !v }
}

// where on the edge a panel of along-length `len` starts, for its `along`
// setting ("start" | "center" | "end" | fraction 0..1 of the free length,
// its centre) between `inset` and `total - inset`
function place(along, len, total, inset) {
    const lo = inset, hi = total - inset - len
    if (hi <= lo) return Math.round((total - len) / 2)
    if (along === "start") return lo
    if (along === "end") return hi
    if (along === "center" || typeof along !== "number") return Math.round((total - len) / 2)
    return Math.round(Math.max(lo, Math.min(hi, along * total - len / 2)))
}

// A rectangle's corner radii from canonical ones — c: { outerStart, outerEnd,
// innerEnd, innerStart } (outer = the screen-edge side, start = left / top end)
// → { tl, tr, br, bl } on the real surface
function corners(edge, c) {
    switch (edge) {
    case "bottom": return { tl: c.innerStart, tr: c.innerEnd, br: c.outerEnd, bl: c.outerStart }
    case "left":   return { tl: c.outerStart, tr: c.innerStart, br: c.innerEnd, bl: c.outerEnd }
    case "right":  return { tl: c.innerStart, tr: c.outerStart, br: c.outerEnd, bl: c.innerEnd }
    default:       return { tl: c.outerStart, tr: c.outerEnd, br: c.innerEnd, bl: c.innerStart }
    }
}

// Qt.matrix4x4 arguments as an object for a QML Matrix4x4 (m: matrix())
function qmatrix(m) { return Qt.matrix4x4(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15]) }

// ── The panel editor's picture of the screen (Part 6.8) ─────────────────────
// s: { w, h } screen; bar: { edge, thickness, gap, inset }
function barRect(s, bar) {
    const T = bar.thickness, G = bar.gap, I = bar.inset
    switch (bar.edge) {
    case "bottom": return { x: I, y: s.h - G - T, w: s.w - 2 * I, h: T }
    case "left":   return { x: G, y: I, w: T, h: s.h - 2 * I }
    case "right":  return { x: s.w - G - T, y: I, w: T, h: s.h - 2 * I }
    default:       return { x: I, y: G, w: s.w - 2 * I, h: T }
    }
}

// Where a panel of screen size w × h shows: p = { edge, offset, along, flare,
// inset } hanging from `edge` at `offset` from it (the bar's gap + thickness,
// or 0 on a bare screen edge), at `along` ("start" | "center" | "end" |
// fraction) — or p = { float: true, x, y } (centre, fractions of the screen).
function panelRect(s, w, h, p) {
    if (p.float) {
        return { x: Math.round(Math.max(0, Math.min(s.w - w, p.x * s.w - w / 2))),
                 y: Math.round(Math.max(0, Math.min(s.h - h, p.y * s.h - h / 2))), w: w, h: h }
    }
    const c = toCanon(p.edge, w, h), total = along(p.edge, s.w, s.h), f = p.flare ?? 0
    const u = p.along === "start" ? p.inset : p.along === "end" ? total - p.inset - c.along
            : place(p.along, c.along + 2 * f, total, p.inset) + f
    return mapRect(p.edge, across(p.edge, s.w, s.h), u, p.offset, c.along, c.depth)
}

// The other way round, for dragging: the `along` a panel gets when its centre
// is at screen position (cx, cy) on `edge` — "start" / "center" / "end" when
// it's within `magnet` px of those places, else a fraction (on the raster).
function alongAt(s, edge, cx, cy, len, inset, flare, magnet, step) {
    const total = along(edge, s.w, s.h), pos = vertical(edge) ? cy : cx
    const at = { start: inset + len / 2, center: total / 2, end: total - inset - len / 2 }
    let best = null, bd = magnet
    for (const k in at) { const d = Math.abs(at[k] - pos); if (d <= bd) { bd = d; best = k } }
    if (best) return best
    const g = step > 0 ? Math.round(pos / step) * step : pos
    return Math.round(g / total * 1000) / 1000
}

// how far (cx, cy) is from the screen edge `edge`, into the screen
function depthOf(s, edge, cx, cy) {
    switch (edge) {
    case "bottom": return s.h - cy
    case "left":   return cx
    case "right":  return s.w - cx
    default:       return cy
    }
}
