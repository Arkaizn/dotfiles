.pragma library
// The offline game (modules/controlcenter/RunnerCard.qml): an endless runner.
// Pure game logic in "art pixels" (the view scales them); the view calls
// step() every frame and draws what the state says. Tested in tests/lib.test.mjs.
//
// state: { phase: "ready" | "run" | "over" | "online",
//          w (field width), y (height above the ground), vy, speed, dist, score,
//          obstacles: [{ x, w, h, kind }] (x = left edge, from the field's left),
//          gap (pixels until the next one is spawned), runner: { x, w, h } }

var gravity = 620          // px / s²
var jumpSpeed = 235        // px / s  → about 44 px high, 0.76 s in the air
var startSpeed = 85        // px / s
var maxSpeed = 190
var accel = 2.2            // px / s per second
// hit boxes are a little smaller than the art: a near miss is a miss
var inset = 3

function create(w, runnerW, runnerH) {
    return { phase: "ready", w: Math.max(80, w), y: 0, vy: 0, speed: startSpeed, dist: 0, score: 0,
             obstacles: [], gap: 90, stop: 0, runner: { x: 10, w: runnerW, h: runnerH } }
}

// kinds: [{ kind, w, h }] the obstacles there are; rnd(): 0 ≤ n < 1
function spawn(s, kinds, rnd) {
    var k = kinds[Math.floor(rnd() * kinds.length) % kinds.length]
    s.obstacles.push({ x: s.w + 2, w: k.w, h: k.h, kind: k.kind })
    // the faster it goes, the more room: always enough to come down behind this
    // one, however wide it is, and jump again
    var air = 2 * jumpSpeed / gravity
    var need = s.speed * air + s.runner.w + k.w
    s.gap = need + rnd() * need * 0.8
}

// Space / click: start, jump (only from the ground), or again after a hit
function press(s) {
    if (s.phase === "ready") { s.phase = "run"; return "start" }
    if (s.phase === "over") {
        if (s.stop < 0.5) return ""            // the key that was held when it hit doesn't restart
        var r = s.runner
        var n = create(s.w, r.w, r.h)
        for (var k in n) s[k] = n[k]
        s.phase = "run"
        return "start"
    }
    if (s.phase === "run" && s.y <= 0) { s.vy = jumpSpeed; s.y = 0.01; return "jump" }
    return ""
}

// the connection is back: no more obstacles, the runner slows to a stop
function online(s) { if (s.phase !== "online") { s.phase = "online"; s.stop = 0 } }

function hits(s) {
    var r = s.runner
    var rl = r.x + inset, rr = r.x + r.w - inset, rb = s.y
    for (var i = 0; i < s.obstacles.length; i++) {
        var o = s.obstacles[i]
        if (rr > o.x + 1 && rl < o.x + o.w - 1 && rb < o.h - 2) return true
    }
    return false
}

// dt in seconds (capped: a stalled frame doesn't jump through an obstacle)
function step(s, dt, kinds, rnd) {
    dt = Math.max(0, Math.min(0.05, dt))
    if (s.phase === "over") { s.stop += dt; return s }
    if (s.phase === "ready") return s
    if (s.phase === "online") {
        s.stop += dt
        s.speed = Math.max(0, s.speed - 160 * dt)
    } else s.speed = Math.min(maxSpeed, s.speed + accel * dt)
    // the jump
    if (s.y > 0 || s.vy > 0) {
        s.vy -= gravity * dt
        s.y += s.vy * dt
        if (s.y <= 0) { s.y = 0; s.vy = 0 }
    }
    var d = s.speed * dt
    s.dist += d
    s.score = Math.floor(s.dist / 8)
    for (var i = 0; i < s.obstacles.length; i++) s.obstacles[i].x -= d
    while (s.obstacles.length > 0 && s.obstacles[0].x + s.obstacles[0].w < -2) s.obstacles.shift()
    if (s.phase === "run") {
        s.gap -= d
        if (s.gap <= 0) spawn(s, kinds, rnd)
        if (hits(s)) { s.phase = "over"; s.stop = 0 }
    }
    return s
}
