.pragma library
// Pixel art as text: a sprite is a list of rows, one character per pixel
// ("." or " " = nothing, any other character = a colour of the palette that
// is given when it's drawn, components/PixelSprite.qml). Pure functions,
// tested in tests/lib.test.mjs.
//
// A sprite sheet ("definition", e.g. PetCat.js) is
//   { id, name, w, h,                      canvas size in pixels; the feet stand on the last row
//     palette: { o: "#d9914a", … },        character → colour (or a Colors role name, see PixelSprite)
//     parts:  { head: [rows], … },         pieces the frames are put together from
//     frames: { walk0: [[part, x, y, recolor?, upsideDown?], …] | [rows] },
//     anims:  { walk: { seq: ["walk0", …], ms: 130, move: [0, 2, …] }, … } }
// A frame is either its rows, or layers of parts (later ones on top);
// recolor: { o: "d" } draws that layer's "o" pixels as "d"; upsideDown (true)
// turns the part on its head (a cat on its back). move: how many steps it
// goes forward in each frame while walking (a bunny only moves in the air).

function isEmpty(c) { return c === "." || c === " " || c === undefined }

function blank(w, h) {
    var out = []
    for (var y = 0; y < h; y++) out.push(new Array(w + 1).join("."))
    return out
}

// layers: [{ rows, x, y, recolor, vflip }] → rows of w × h (what sticks out is cut off)
function compose(w, h, layers) {
    var grid = []
    for (var y = 0; y < h; y++) { grid.push([]); for (var x = 0; x < w; x++) grid[y].push(".") }
    for (var i = 0; i < layers.length; i++) {
        var l = layers[i], rows = l.rows || []
        if (l.vflip) rows = rows.slice().reverse()
        for (var ry = 0; ry < rows.length; ry++) {
            var gy = ry + (l.y || 0)
            if (gy < 0 || gy >= h) continue
            for (var rx = 0; rx < rows[ry].length; rx++) {
                var c = rows[ry][rx], gx = rx + (l.x || 0)
                if (isEmpty(c) || gx < 0 || gx >= w) continue
                grid[gy][gx] = l.recolor && l.recolor[c] !== undefined ? l.recolor[c] : c
            }
        }
    }
    return grid.map(function (r) { return r.join("") })
}

// mirrored left ↔ right (a pet walking the other way)
function flip(rows) {
    return rows.map(function (r) { return r.split("").reverse().join("") })
}

// horizontal runs of one colour: [{ x, y, n, c }] — what gets drawn (one
// rectangle per run instead of one per pixel)
function runs(rows) {
    var out = []
    for (var y = 0; y < rows.length; y++) {
        var r = rows[y], x = 0
        while (x < r.length) {
            var c = r[x]
            if (isEmpty(c)) { x++; continue }
            var n = 1
            while (x + n < r.length && r[x + n] === c) n++
            out.push({ x: x, y: y, n: n, c: c })
            x += n
        }
    }
    return out
}

var _cache = {}

// the rows of a definition's frame ([] when it doesn't exist)
function frame(def, name) {
    var key = def.id + "/" + name
    if (_cache[key]) return _cache[key]
    var f = def.frames[name]
    if (!f) return []
    var rows
    if (f.length > 0 && typeof f[0] === "string") rows = compose(def.w, def.h, [{ rows: f, x: 0, y: 0 }])
    else rows = compose(def.w, def.h, f.map(function (l) {
        return { rows: def.parts[l[0]] || [], x: l[1] || 0, y: l[2] || 0, recolor: l[3], vflip: l[4] === true }
    }))
    _cache[key] = rows
    return rows
}

// the frame an animation shows after `ms` (it loops)
function frameAt(def, anim, ms) {
    var a = def.anims[anim]
    if (!a || a.seq.length === 0) return ""
    return a.seq[Math.floor(Math.max(0, ms) / a.ms) % a.seq.length]
}

// which frame of the animation that is (0, 1, …)
function indexAt(def, anim, ms) {
    var a = def.anims[anim]
    if (!a || a.seq.length === 0) return 0
    return Math.floor(Math.max(0, ms) / a.ms) % a.seq.length
}

// the pieces that hang together (4 neighbours): 1 = one body, nothing detached
function pieces(rows) {
    var h = rows.length, w = h ? rows[0].length : 0, seen = {}, n = 0
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
        if (isEmpty(rows[y][x]) || seen[y * w + x]) continue
        n++
        var todo = [[x, y]]
        seen[y * w + x] = true
        while (todo.length) {
            var p = todo.pop()
            var near = [[p[0] + 1, p[1]], [p[0] - 1, p[1]], [p[0], p[1] + 1], [p[0], p[1] - 1]]
            for (var i = 0; i < 4; i++) {
                var nx = near[i][0], ny = near[i][1]
                if (nx < 0 || ny < 0 || nx >= w || ny >= h || isEmpty(rows[ny][nx]) || seen[ny * w + nx]) continue
                seen[ny * w + nx] = true
                todo.push([nx, ny])
            }
        }
    }
    return n
}

// a definition's palette with one of its coats laid over it
function coatPalette(def, coatId) {
    var out = {}
    for (var k in def.palette) out[k] = def.palette[k]
    var c = (def.coats || []).filter(function (x) { return x.id === coatId })[0]
    if (c) for (var j in c.colors) out[j] = c.colors[j]
    return out
}

// ── frames as images ────────────────────────────────────────────────────────
// A frame is turned into a tiny PNG (one pixel per art pixel) once and kept;
// PixelSprite shows it as an Image, scaled up without smoothing. Showing
// another frame is then a texture swap, nothing is drawn again.

var _crc = null
function crc32(bytes, from, to) {
    if (!_crc) {
        _crc = []
        for (var n = 0; n < 256; n++) { var c = n; for (var k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; _crc.push(c >>> 0) }
    }
    var v = 0xffffffff
    for (var i = from; i < to; i++) v = _crc[(v ^ bytes[i]) & 255] ^ (v >>> 8)
    return (v ^ 0xffffffff) >>> 0
}
var _b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function base64(bytes) {
    var out = ""
    for (var i = 0; i < bytes.length; i += 3) {
        var a = bytes[i], b = i + 1 < bytes.length ? bytes[i + 1] : 0, c = i + 2 < bytes.length ? bytes[i + 2] : 0
        out += _b64[a >> 2] + _b64[((a & 3) << 4) | (b >> 4)] + (i + 1 < bytes.length ? _b64[((b & 15) << 2) | (c >> 6)] : "=") + (i + 2 < bytes.length ? _b64[c & 63] : "=")
    }
    return out
}
// "#rgb", "#rrggbb" or "#aarrggbb" (what QML makes of a colour) → [r, g, b, a]
function rgba(col) {
    var h = String(col || "").replace("#", "")
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
    if (h.length === 6) h = "ff" + h
    if (!/^[0-9a-fA-F]{8}$/.test(h)) return [255, 0, 255, 255]
    return [parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16), parseInt(h.substr(6, 2), 16), parseInt(h.substr(0, 2), 16)]
}
// rows + { character: colour } → the bytes of a PNG (8-bit RGBA, not compressed: it's tiny)
function pngBytes(rows, colors) {
    var h = rows.length, w = h ? rows[0].length : 0
    var raw = []
    var cache = {}
    for (var y = 0; y < h; y++) {
        raw.push(0)
        for (var x = 0; x < w; x++) {
            var c = rows[y][x]
            if (isEmpty(c)) { raw.push(0, 0, 0, 0); continue }
            var p = cache[c] || (cache[c] = rgba(colors[c]))
            raw.push(p[0], p[1], p[2], p[3])
        }
    }
    // zlib: one stored block, then the Adler-32 of the data
    var a = 1, b = 0
    for (var i = 0; i < raw.length; i++) { a = (a + raw[i]) % 65521; b = (b + a) % 65521 }
    var len = raw.length
    var z = [0x78, 0x01, 1, len & 255, len >> 8, ~len & 255, (~len >> 8) & 255].concat(raw, [b >> 8, b & 255, a >> 8, a & 255])
    var u32 = function (v) { return [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255] }
    var chunk = function (type, data) {
        var td = [type.charCodeAt(0), type.charCodeAt(1), type.charCodeAt(2), type.charCodeAt(3)].concat(data)
        return u32(data.length).concat(td, u32(crc32(td, 0, td.length)))
    }
    return [137, 80, 78, 71, 13, 10, 26, 10].concat(chunk("IHDR", u32(w).concat(u32(h), [8, 6, 0, 0, 0])), chunk("IDAT", z), chunk("IEND", []))
}
var _png = {}
var pngMade = 0             // how many were built (the rest came from the cache)
// the frame as a data: URL for an Image; built once per frame and set of colours
function png(rows, colors) {
    if (!rows || rows.length === 0 || rows.length * rows[0].length > 65000 / 4) return ""
    var used = {}, key = rows.join("/")
    for (var y = 0; y < rows.length; y++) for (var x = 0; x < rows[y].length; x++) if (!isEmpty(rows[y][x])) used[rows[y][x]] = true
    var cols = {}
    Object.keys(used).sort().forEach(function (c) { cols[c] = String(colors[c] || ""); key += "|" + c + cols[c] })
    if (_png[key]) return _png[key]
    pngMade++
    return (_png[key] = "data:image/png;base64," + base64(pngBytes(rows, cols)))
}

// what's wrong with a definition ([] = fine): `needs` = animations it must have
function check(def, needs) {
    var bad = []
    if (!def || typeof def.id !== "string" || !def.id) return ["no id"]
    if (!(def.w > 0 && def.h > 0)) bad.push("no size")
    var chars = {}
    var note = function (rows, where) {
        for (var y = 0; y < rows.length; y++)
            for (var x = 0; x < rows[y].length; x++) if (!isEmpty(rows[y][x])) chars[rows[y][x]] = where
    }
    for (var p in def.parts || {}) {
        var rows = def.parts[p]
        if (rows.some(function (r) { return r.length !== rows[0].length })) bad.push("part " + p + ": rows differ in length")
        note(rows, "part " + p)
    }
    for (var f in def.frames || {}) {
        var fr = def.frames[f]
        if (fr.length > 0 && typeof fr[0] === "string") {
            if (fr.length !== def.h || fr.some(function (r) { return r.length !== def.w })) bad.push("frame " + f + ": not " + def.w + " × " + def.h)
            note(fr, "frame " + f)
            continue
        }
        for (var i = 0; i < fr.length; i++) {
            if (!def.parts || !def.parts[fr[i][0]]) bad.push("frame " + f + ": no part " + fr[i][0])
            for (var k in fr[i][3] || {}) chars[fr[i][3][k]] = "frame " + f
        }
    }
    for (var c in chars) if (!def.palette || def.palette[c] === undefined) bad.push(chars[c] + ": colour \"" + c + "\" isn't in the palette")
    for (var a in def.anims || {}) {
        var an = def.anims[a]
        if (!(an.ms >= 40)) bad.push("anim " + a + ": ms must be 40 or more")
        if (!an.seq || an.seq.length === 0) bad.push("anim " + a + ": no frames")
        else an.seq.forEach(function (n) { if (!def.frames[n]) bad.push("anim " + a + ": no frame " + n) })
    }
    ;(needs || []).forEach(function (n) { if (!def.anims || !def.anims[n]) bad.push("no animation \"" + n + "\"") })
    return bad
}
