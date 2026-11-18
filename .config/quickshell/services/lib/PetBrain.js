.pragma library
// What a desktop pet does next (modules/pets/Pet.qml runs it). Pure: the
// random numbers come in, so it can be tested.
//
// States: sleep · lie · sit · stand · walk · follow (after the pointer) ·
// happy · alert (a notification, or "what do you want?") · stretch · roll.
// A state lasts `ms` (0 = until something happens). Pets rest: most of the
// time they lie or nap, now and then they get up for a short walk.
//
// How an animal behaves is its `nature` (in its definition, PetCat.js …):
//   stepMs    ms per step while it moves (smaller = faster)
//   rest      0…1, how much it prefers lying down to getting up
//   walkMs    [min, max] length of a walk
//   napMs     [min, max] length of a nap while you're there
//   follow    0…1, how likely it comes when called (clicked / dragged)
//   followMs  [min, max] how long it stays with the pointer
//   ignores   what it does when it doesn't come: "stretch", "roll", "look"
//   arrive    what it does next to the pointer: "happy", "sit" or "sleep"

var states = ["sleep", "lie", "sit", "stand", "walk", "follow", "happy", "alert", "stretch", "roll"]
// animations every definition must have
var needs = ["walk", "stand", "sit", "lie", "sleep", "happy", "alert", "run", "jump", "hit"]
var sizes = { small: 2, medium: 3, large: 4 }
var places = ["bar", "screen"]
var resting = { sleep: true, lie: true, sit: true }

function between(range, r) { return Math.round(range[0] + (range[1] - range[0]) * r) }
function natureOf(n) {
    n = n || {}
    return { stepMs: n.stepMs > 0 ? n.stepMs : 80, rest: n.rest >= 0 ? Math.min(0.98, n.rest) : 0.85,
             walkMs: n.walkMs || [1200, 3000], napMs: n.napMs || [30000, 100000],
             follow: n.follow >= 0 ? n.follow : 0.5, followMs: n.followMs || [5000, 9000],
             ignores: n.ignores || ["look"], arrive: n.arrive || "sit" }
}

// cur: the state that just ended; ctx: { idle (you're away), dir (1 right, -1 left), nature }
// rnd(): 0 ≤ n < 1  →  { state, ms, dir }
function next(cur, ctx, rnd) {
    var dir = ctx.dir === -1 ? -1 : 1
    var n = natureOf(ctx.nature)
    var go = function (state, ms, d) { return { state: state, ms: ms, dir: d || dir } }
    if (ctx.idle) {
        // lies down first, then sleeps until you're back
        if (cur === "lie" || cur === "sleep") return go("sleep", 0)
        return go("lie", between([1200, 2600], rnd()))
    }
    var r = rnd()
    switch (cur) {
    case "sleep":          // waking up: eyes open, still lying
        return go("lie", between([4000, 15000], rnd()))
    case "lie":
        if (r < n.rest * 0.75) return go("sleep", between(n.napMs, rnd()))
        return r < n.rest ? go("sit", between([4000, 12000], rnd())) : go("stand", between([800, 2000], rnd()))
    case "sit":
        if (r < n.rest) return go("lie", between([8000, 30000], rnd()))
        return go("stand", between([800, 2000], rnd()))
    case "stand":
        if (r < 0.55) return go("walk", between(n.walkMs, rnd()), rnd() < 0.5 ? -dir : dir)
        return r < 0.8 ? go("sit", between([4000, 12000], rnd())) : go("lie", between([8000, 30000], rnd()))
    case "stretch":
    case "roll":           // back to what it was doing: nothing
        return go("sleep", between(n.napMs, rnd()))
    case "follow":
    case "happy":
        return go(r < 0.5 ? "sit" : "lie", between([5000, 14000], rnd()))
    case "alert":
        return go("lie", between([5000, 14000], rnd()))
    default:               // a walk is followed by a rest, never by another walk
        return r < 0.4 ? go("sit", between([4000, 12000], rnd())) : go("lie", between([8000, 30000], rnd()))
    }
}

// called (clicked or dragged): does it come?  has: the animations it has
//   → { state: "follow" | "stretch" | "roll" | "alert" | "sleep", ms }
function called(nature, has, rnd) {
    var n = natureOf(nature)
    if (rnd() < n.follow) return { state: "follow", ms: between(n.followMs, rnd()) }
    var can = n.ignores.filter(function (i) { return i === "look" || (has && has[i]) })
    var pick = can.length ? can[Math.floor(rnd() * can.length) % can.length] : "look"
    if (pick === "stretch") return { state: "stretch", ms: between([1600, 2600], rnd()) }
    if (pick === "roll") return { state: "roll", ms: between([2500, 4500], rnd()) }
    return { state: "alert", ms: between([900, 1600], rnd()) }
}

// one step of `step` pixels inside [min, max]: turns round at the ends → { x, dir }
function walk(x, dir, step, min, max) {
    if (max <= min) return { x: min, dir: dir }
    var nx = x + dir * step
    if (nx > max) return { x: max, dir: -1 }
    if (nx < min) return { x: min, dir: 1 }
    return { x: nx, dir: dir }
}

// one step towards `target` (its left edge there): → { x, dir, there }
// `reach`: close enough (it stops instead of jittering around the pointer)
function toward(x, target, step, min, max, reach) {
    var t = Math.max(min, Math.min(max, target))
    var d = t - x
    if (Math.abs(d) <= Math.max(reach, step)) return { x: x, dir: d < 0 ? -1 : 1, there: true }
    var nx = x + (d > 0 ? step : -step)
    return { x: Math.max(min, Math.min(max, nx)), dir: d > 0 ? 1 : -1, there: false }
}

// where to rest on a bar: the free stretches between its buttons.
//   width: the bar; taken: [[x0, x1], …] the buttons' groups; need: the pet's width
//   → [[x0, x1], …] left edges it can lie at (each wide enough), widest first
function gaps(width, taken, need, pad) {
    pad = pad || 0
    var list = (taken || []).filter(function (t) { return t[1] > t[0] }).map(function (t) { return [t[0] - pad, t[1] + pad] })
    list.sort(function (a, b) { return a[0] - b[0] })
    var out = [], at = pad
    for (var i = 0; i <= list.length; i++) {
        var end = i < list.length ? list[i][0] : width - pad
        if (end - at >= need) out.push([at, end - need])
        if (i < list.length) at = Math.max(at, list[i][1])
    }
    out.sort(function (a, b) { return (b[1] - b[0]) - (a[1] - a[0]) })
    return out
}

// the place in `spots` nearest to x (x itself when it's inside one, or there are none)
function nearestSpot(x, spots) {
    var best = x, bestD = Infinity
    for (var i = 0; i < (spots || []).length; i++) {
        var s = spots[i]
        var c = Math.max(s[0], Math.min(s[1], x))
        if (Math.abs(c - x) < bestD) { bestD = Math.abs(c - x); best = c }
    }
    return best
}

// ── settings.json check ("pets" group) ──────────────────────────────────────
// { enabled, animals: [ids], coats: { id: coat }, place, monitors: [ids] ([] = all), size, layer,
//   sleepAfter (minutes), react, game, runner }
// animals: [{ id, coats: [{ id }] }] the definitions; err(path, message)
function validate(v, animals, err) {
    var ids = animals.map(function (a) { return a.id })
    var isBool = function (x) { return typeof x === "boolean" }
    for (var k in v) {
        var x = v[k]
        if (k === "enabled" || k === "react" || k === "game") { if (!isBool(x)) err([k], k + " must be true or false") }
        else if (k === "animals") {
            if (!Array.isArray(x)) err([k], "animals must be a list (" + ids.join(", ") + ")")
            else x.forEach(function (a) { if (ids.indexOf(a) < 0) err([k], "unknown animal " + JSON.stringify(a) + " (" + ids.join(", ") + ")") })
        }
        else if (k === "coats") {
            if (x === null || typeof x !== "object" || Array.isArray(x)) { err([k], "coats must be { animal: coat }"); continue }
            for (var a in x) {
                var def = animals.filter(function (d) { return d.id === a })[0]
                if (!def) err([k, a], "unknown animal \"" + a + "\" (" + ids.join(", ") + ")")
                else if (!(def.coats || []).some(function (c) { return c.id === x[a] }))
                    err([k, a], a + " has no coat " + JSON.stringify(x[a]) + " (" + (def.coats || []).map(function (c) { return c.id }).join(", ") + ")")
            }
        }
        else if (k === "monitors") {
            if (!Array.isArray(x) || x.some(function (m) { return typeof m !== "string" || m.trim() === "" }))
                err([k], "monitors must be a list of monitor names (\"make model serial\")")
        }
        else if (k === "place") { if (places.indexOf(x) < 0) err([k], "place is bar or screen") }
        else if (k === "size") { if (sizes[x] === undefined) err([k], "size is small, medium or large") }
        else if (k === "layer") { if (x !== "top" && x !== "bottom") err([k], "layer is top or bottom") }
        else if (k === "sleepAfter") { if (!(Number.isInteger(x) && x >= 1 && x <= 120)) err([k], "sleepAfter is 1–120 minutes") }
        else if (k === "runner") { if (ids.indexOf(x) < 0) err([k], "runner is one of " + ids.join(", ")) }
        else err([k], "unknown setting \"" + k + "\"")
    }
}
