.pragma library

// Pure geometry of the live editors (Part 6, panel editor): raster, guides,
// the magnetic pull of a dragged part towards its slot, which screen edge a
// point is nearest to, size limits. No highlights anywhere — callers only
// move things to where these functions say, with an animation.

// nearest multiple of `step` (step <= 0: unchanged)
function grid(v, step) {
    return step > 0 ? Math.round(v / step) * step : v
}

// v snapped to the nearest of `targets` within `dist`, else to the raster.
// → { value, guide } (guide: the target it snapped to, or null)
function snap1(v, targets, dist, step) {
    let best = null, bd = dist
    for (const t of targets ?? []) {
        const d = Math.abs(t - v)
        if (d <= bd) { bd = d; best = t }
    }
    return best !== null ? { value: best, guide: best } : { value: grid(v, step), guide: null }
}

// A rectangle's position snapped: its left edge, centre or right edge to a
// vertical guide (same for y), else its left / top edge to the raster.
//   r: { x, y, w, h }   guides: { x: [..], y: [..] }
// → { x, y, gx, gy } (gx / gy: the guide used, or null)
function snapRect(r, guides, dist, step) {
    const ax = axis(r.x, r.w, guides?.x ?? [], dist, step)
    const ay = axis(r.y, r.h, guides?.y ?? [], dist, step)
    return { x: ax.pos, y: ay.pos, gx: ax.guide, gy: ay.guide }
}
function axis(pos, size, targets, dist, step) {
    let best = null, bd = dist
    for (const t of targets) {
        for (const off of [0, size / 2, size]) {
            const d = Math.abs(t - (pos + off))
            if (d <= bd) { bd = d; best = { pos: t - off, guide: t } }
        }
    }
    return best ?? { pos: grid(pos, step), guide: null }
}

// guides of a screen: edges (after `inset`) and the centre lines
function screenGuides(w, h, inset) {
    const i = inset ?? 0
    return { x: [i, w / 2, w - i], y: [i, h / 2, h - i] }
}

// smoothstep 0..1
function ease(t) {
    const c = Math.max(0, Math.min(1, t))
    return c * c * (3 - 2 * c)
}

// The magnet: a dragged part at `p` is pulled towards `slot` once it's within
// `radius`; inside `radius * inner` it sits on the slot. Points: { x, y }.
// Outside the radius it's exactly at p (moving away pulls it out again).
function pull(p, slot, radius, inner) {
    if (!slot || !(radius > 0)) return { x: p.x, y: p.y }
    const dx = slot.x - p.x, dy = slot.y - p.y
    const d = Math.hypot(dx, dy)
    if (d >= radius) return { x: p.x, y: p.y }
    const core = radius * (inner ?? 0.35)
    const t = d <= core ? 1 : ease(1 - (d - core) / (radius - core))
    return { x: p.x + dx * t, y: p.y + dy * t }
}

// screen edge nearest to the point (x, y) on a w × h screen
function nearestEdge(x, y, w, h) {
    const d = { top: y, bottom: h - y, left: x, right: w - x }
    return Object.keys(d).reduce((a, b) => d[b] < d[a] ? b : a)
}
function vertical(edge) { return edge === "left" || edge === "right" }

// v kept within [min, max] (max < min: min wins)
function clamp(v, min, max) {
    return Math.max(min, Math.min(Math.max(min, max), v))
}

// a resize: the size after dragging a handle by `delta`, on the raster, in limits
function resize(size, delta, min, max, step) {
    return clamp(grid(size + delta, step), min, max)
}
