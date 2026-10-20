.pragma library

// Desktop widgets: geometry, snapping, monitor matching and the settings check
// (no QML, unit-tested). An instance:
//   { id, type, x, y,        centre, 0..1 of the screen (survives resolution / scale changes)
//     rot,                   degrees, -180..180
//     scale,                 0.4..3
//     monitors,              null = like all widgets; [] = every monitor; ["make model serial" | output name, …]
//     opts }                 the type's options (DesktopWidgets.types)

const GRID = 16              // px: Ctrl-drag snaps the edges to this grid (not drawn)
const SNAP_DIST = 8          // px: Ctrl-drag snaps to another widget's / the screen's edge within this
const ROT_STEP = 15          // degrees: Ctrl-rotate steps
const ROT_STICK = 4          // degrees: rotation sticks to 0 / 90 / … within this, without Ctrl
const SCALE_MIN = 0.4, SCALE_MAX = 3

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)) }

function snap(v, grid) { return Math.round(v / (grid || GRID)) * (grid || GRID) }

// Ctrl-drag: the widget's box (centre x, y; size w, h) snaps with its edges or
// centre to the edges / centres of `others` ([{ x, y, w, h }]) and of the screen
// (sw × sh) when one is within SNAP_DIST; otherwise its left / top edge goes on
// the grid. → { x, y, guides: [{ axis: "x" | "y", pos }] } (guides: widget /
// screen snaps only, the grid isn't drawn)
function snapBox(x, y, w, h, others, sw, sh) {
    const out = { x: x, y: y, guides: [] }
    const axis = (c, size, key, len, screen) => {
        const mine = [c - size / 2, c, c + size / 2]
        const targets = [0, screen / 2, screen]
        for (const o of others) targets.push(o[key] - o[len] / 2, o[key], o[key] + o[len] / 2)
        let best = null
        for (const t of targets)
            for (const m of mine)
                if (Math.abs(t - m) <= SNAP_DIST && (best === null || Math.abs(t - m) < Math.abs(best.d))) best = { d: t - m, pos: t }
        if (best) { out.guides.push({ axis: key, pos: best.pos }); return c + best.d }
        const edge = c - size / 2
        return c + snap(edge) - edge
    }
    out.x = axis(x, w, "x", "w", sw)
    out.y = axis(y, h, "y", "h", sh)
    return out
}

// degrees, normalised to -180..180; ctrl: 15° steps, else sticks to right angles
function snapAngle(deg, ctrl) {
    let a = ((deg % 360) + 540) % 360 - 180
    if (ctrl) a = Math.round(a / ROT_STEP) * ROT_STEP
    else {
        const r = Math.round(a / 90) * 90
        if (Math.abs(a - r) <= ROT_STICK) a = r
    }
    if (a === -180) a = 180
    return a === 0 ? 0 : a      // no -0
}

// the angle (degrees, 0 = up, clockwise) of point (px, py) seen from (cx, cy)
function angleOf(cx, cy, px, py) { return Math.atan2(px - cx, -(py - cy)) * 180 / Math.PI }

function snapScale(s, ctrl) {
    s = clamp(s, SCALE_MIN, SCALE_MAX)
    return ctrl ? Math.round(s * 10) / 10 : Math.round(s * 100) / 100
}

// width / height of the box around a w × h rectangle rotated by deg
function bounds(w, h, deg) {
    const r = Math.abs(deg) * Math.PI / 180
    const c = Math.abs(Math.cos(r)), s = Math.abs(Math.sin(r))
    return { w: Math.ceil(w * c + h * s - 1e-6), h: Math.ceil(w * s + h * c - 1e-6) }     // no 51 for 50.000…1
}

// a centre in px → 0..1, kept on the screen
function toRel(px, size) { return size > 0 ? Math.round(clamp(px / size, 0, 1) * 10000) / 10000 : 0.5 }

// does a widget with these monitors show on screen `name`?
//   ids: [] = every monitor; outputs: Monitors.outputs [{ name, ident }]
function showsOn(ids, name, outputs) {
    if (!ids || ids.length === 0) return true
    return ids.some(id => id === name || (outputs || []).some(o => o.name === name && o.ident === id))
}

function newId(type, taken) {
    let n = 1
    while ((taken || []).includes(type + "-" + n)) n++
    return type + "-" + n
}

// ── settings.json check ─────────────────────────────────────────────────────
// desktopWidgets: { enabled, monitors, instances }; types: { <type>: [option specs] }
//   option spec: { key, kind: "bool" | "number" | "text" | "choice" | "list", min, max, choices }
function checkOpt(spec, v) {
    switch (spec.kind) {
    case "bool": return typeof v === "boolean" ? "" : "true or false"
    case "number": return typeof v === "number" && isFinite(v) && v >= spec.min && v <= spec.max ? "" : spec.min + "–" + spec.max
    case "text": return typeof v === "string" && v.length <= 4000 ? "" : "text (at most 4000 characters)"
    case "choice": return spec.choices.some(c => c.value === v) ? "" : "one of " + spec.choices.map(c => c.value).join(", ")
    case "list": return Array.isArray(v) && v.length <= 32 && v.every(x => typeof x === "string") ? "" : "a list of texts"
    }
    return "unknown kind"
}

function isMonitorList(v) { return Array.isArray(v) && v.every(x => typeof x === "string" && x.trim() !== "") }

function validate(v, types, err) {
    for (const k of Object.keys(v)) {
        if (k === "enabled") { if (typeof v[k] !== "boolean") err([k], "enabled must be true or false") }
        else if (k === "monitors") { if (!isMonitorList(v[k])) err([k], "monitors must be a list of monitor names (\"make model serial\")") }
        else if (k === "instances") {
            if (!Array.isArray(v[k])) { err([k], "instances must be a list"); continue }
            const ids = []
            v[k].forEach((w, i) => {
                const at = (f, m) => err([k, i].concat(f === "" ? [] : [f]), m)
                if (w === null || typeof w !== "object" || Array.isArray(w)) { at("", "a widget is an object"); return }
                if (typeof w.id !== "string" || w.id === "") at("id", "id is a text")
                else if (ids.includes(w.id)) at("id", "id \"" + w.id + "\" is used twice")
                else ids.push(w.id)
                const specs = types[w.type]
                if (!specs) { at("type", "unknown widget type \"" + w.type + "\""); return }
                for (const f of Object.keys(w)) {
                    if (f === "id" || f === "type") continue
                    if (f === "x" || f === "y") { if (typeof w[f] !== "number" || !(w[f] >= 0 && w[f] <= 1)) at(f, f + " is 0–1 (part of the screen)") }
                    else if (f === "rot") { if (typeof w[f] !== "number" || !(w[f] >= -180 && w[f] <= 180)) at(f, "rot is -180–180 degrees") }
                    else if (f === "scale") { if (typeof w[f] !== "number" || !(w[f] >= SCALE_MIN && w[f] <= SCALE_MAX)) at(f, "scale is " + SCALE_MIN + "–" + SCALE_MAX) }
                    else if (f === "monitors") { if (w[f] !== null && !isMonitorList(w[f])) at(f, "monitors is null (like all widgets) or a list of monitor names") }
                    else if (f === "opts") {
                        if (w[f] === null || typeof w[f] !== "object" || Array.isArray(w[f])) { at(f, "opts is an object"); continue }
                        for (const o of Object.keys(w[f])) {
                            const spec = specs.find(s => s.key === o)
                            if (!spec) { err([k, i, f, o], "unknown option \"" + o + "\" for " + w.type); continue }
                            const m = checkOpt(spec, w[f][o])
                            if (m !== "") err([k, i, f, o], o + ": " + m)
                        }
                    }
                    else at(f, "unknown field \"" + f + "\"")
                }
            })
        }
        else err([k], "unknown setting \"" + k + "\"")
    }
}
