.pragma library

// Where the bar sits and how big / where the panels are (Part 6, panel
// editor). Settings.panels holds only what differs from these defaults:
//   bar:           { edge: "top"|"bottom"|"left"|"right", thickness }
//   dashboard:     { width, height (0 = as the cards need), attach, along, x, y }
//   controlCenter: { width, attach, along, x, y }
//   notifications: { height }  (most the list grows to, then it scrolls)
//   launcher:      { attach, along, x, y, views: { <view>: { w, h } } }
//   cards:         { <control center card id>: { perRow, tile } }  (button cards:
//                  tiles per row, tile height; the buttons share the row)
// attach: "bar" = hangs from the bar (inverted corners); "edge" (launcher
// only, its old place) = from the screen edge opposite the bar, inverted
// corners against the screen edge; "float" = anywhere, all corners round.
// along: where on the bar / edge — "start" | "center" | "end" (flush with
// that end) or a fraction 0..1 of its length (the panel's centre).
// x, y (float): the panel's centre as a fraction of the screen.

var edges = ["top", "bottom", "left", "right"]
var attaches = ["bar", "edge", "float"]
var launcherViews = ["apps", "clipboard", "connections", "wallpapers", "keybinds"]

var defaults = {
    bar: { edge: "top", thickness: 50 },
    dashboard: { width: 1070, height: 0, attach: "bar", along: "center", x: 0.5, y: 0.5 },
    controlCenter: { width: 420, attach: "bar", along: "end", x: 0.5, y: 0.5 },
    notifications: { height: 420 },
    launcher: { attach: "edge", along: "center", x: 0.5, y: 0.5, views: {
        apps: { w: 640, h: 360 }, clipboard: { w: 640, h: 360 }, connections: { w: 640, h: 360 },
        wallpapers: { w: 960, h: 520 }, keybinds: { w: 960, h: 520 } } }
}

var cardDefaults = { perRow: 3, tile: 56 }

// [min, max] of each number (0 allowed where noted: "as the content needs")
var limits = {
    "bar.thickness": [36, 96],
    "dashboard.width": [960, 3000], "dashboard.height": [300, 2000],
    "controlCenter.width": [340, 900],
    "notifications.height": [120, 1600],
    "view.w": [400, 2400], "view.h": [160, 1400],
    "card.perRow": [1, 6], "card.tile": [40, 120]
}
var zeroOk = { "dashboard.height": true }

function num(v, key) {
    if (typeof v !== "number" || !isFinite(v)) return null
    if (v === 0 && zeroOk[key]) return 0
    const l = limits[key]
    return l ? Math.round(Math.max(l[0], Math.min(l[1], v))) : v
}
function frac(v) { return typeof v === "number" && isFinite(v) ? Math.max(0, Math.min(1, v)) : null }
function along(v) {
    if (v === "start" || v === "center" || v === "end") return v
    return frac(v)
}

// a panel's settings merged over the defaults, bad values dropped
function panel(stored, id) {
    const d = defaults[id]
    const s = stored && typeof stored === "object" ? stored : {}
    const out = {}
    for (const k in d) {
        if (k === "views") continue
        const v = s[k]
        let ok = null
        if (k === "edge") ok = edges.includes(v) ? v : null
        else if (k === "attach") ok = attaches.includes(v) && (id === "launcher" || v !== "edge") ? v : null
        else if (k === "along") ok = along(v)
        else if (k === "x" || k === "y") ok = frac(v)
        else ok = num(v, id + "." + k)
        out[k] = ok === null ? d[k] : ok
    }
    if (id === "launcher") {
        out.views = {}
        const sv = s.views && typeof s.views === "object" ? s.views : {}
        for (const v of launcherViews) {
            const dv = d.views[v], given = sv[v] && typeof sv[v] === "object" ? sv[v] : {}
            out.views[v] = { w: num(given.w, "view.w") ?? dv.w, h: num(given.h, "view.h") ?? dv.h }
        }
    }
    return out
}

// one button card's size merged over the defaults
function card(stored) {
    const s = stored && typeof stored === "object" ? stored : {}
    return { perRow: num(s.perRow, "card.perRow") ?? cardDefaults.perRow, tile: num(s.tile, "card.tile") ?? cardDefaults.tile }
}
function cardId(id) { return typeof id === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(id) }

// all of it at once (cards: only the stored ones; card() for the rest)
function resolve(stored) {
    const s = stored && typeof stored === "object" ? stored : {}
    const out = {}
    for (const id in defaults) out[id] = panel(s[id], id)
    out.cards = {}
    const c = s.cards && typeof s.cards === "object" ? s.cards : {}
    for (const id in c) if (cardId(id)) out.cards[id] = card(c[id])
    return out
}

// a button card's value set: the new stored `cards` object (null = empty)
function storeCard(cards, id, key, value) {
    const out = Object.assign({}, cards && typeof cards === "object" ? cards : {})
    const c = card(Object.assign({}, out[id], { [key]: value }))
    const o = {}
    if (c.perRow !== cardDefaults.perRow) o.perRow = c.perRow
    if (c.tile !== cardDefaults.tile) o.tile = c.tile
    if (Object.keys(o).length) out[id] = o; else delete out[id]
    return Object.keys(out).length ? out : null
}

// one value set: the new stored object for that panel, with only what differs
// from the default kept (null = nothing left, reset the key)
function store(stored, id, key, value) {
    const cur = Object.assign({}, stored && typeof stored === "object" ? stored : {})
    cur[key] = value
    const clean = panel(cur, id)
    const out = {}
    for (const k in clean) {
        if (k === "views") {
            const vs = {}
            for (const v of launcherViews) {
                const dv = defaults.launcher.views[v], cv = clean.views[v]
                const o = {}
                if (cv.w !== dv.w) o.w = cv.w
                if (cv.h !== dv.h) o.h = cv.h
                if (Object.keys(o).length) vs[v] = o
            }
            if (Object.keys(vs).length) out.views = vs
        } else if (clean[k] !== defaults[id][k]) out[k] = clean[k]
    }
    return Object.keys(out).length ? out : null
}

// import check of the whole group: "" = fine, else what's wrong
function validate(v) {
    if (!v || typeof v !== "object" || Array.isArray(v)) return "panels: not an object"
    for (const id in v) {
        if (id === "cards") {
            const c = v.cards
            if (!c || typeof c !== "object" || Array.isArray(c)) return "panels.cards: not an object"
            for (const k in c) {
                if (!cardId(k) || !c[k] || typeof c[k] !== "object") return "panels.cards." + k + ": bad card"
                for (const f in c[k]) if (!(f in cardDefaults) || num(c[k][f], "card." + f) === null) return "panels.cards." + k + "." + f + ": bad value"
            }
            continue
        }
        if (!(id in defaults)) return "panels: unknown part \"" + id + "\""
        const p = v[id]
        if (!p || typeof p !== "object" || Array.isArray(p)) return "panels." + id + ": not an object"
        for (const k in p) {
            if (!(k in defaults[id])) return "panels." + id + ": unknown key \"" + k + "\""
            const x = p[k]
            const bad = k === "edge" ? !edges.includes(x)
                : k === "attach" ? !attaches.includes(x)
                : k === "along" ? along(x) === null
                : k === "x" || k === "y" ? frac(x) === null
                : k === "views" ? !viewsOk(x)
                : num(x, id + "." + k) === null
            if (bad) return "panels." + id + "." + k + ": bad value"
        }
    }
    return ""
}
function viewsOk(x) {
    if (!x || typeof x !== "object") return false
    for (const v in x) {
        if (!launcherViews.includes(v) || !x[v] || typeof x[v] !== "object") return false
        for (const k in x[v]) if ((k !== "w" && k !== "h") || num(x[v][k], "view." + k) === null) return false
    }
    return true
}
