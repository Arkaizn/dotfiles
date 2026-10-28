.pragma library

// Small JSON parser for the settings import. Same result as JSON.parse, but a
// syntax error says where it is ({ line, col, message } is thrown), and the
// line of every key is kept in `lines` (key: JSON.stringify(path)) so the
// checks after parsing can point at the line of a bad value too.
function parse(text) {
    let i = 0, line = 1, col = 1
    const lines = {}

    function fail(msg, ln, cl) { throw { line: ln ?? line, col: cl ?? col, message: msg } }
    function next() {
        const c = text[i++]
        if (c === "\n") { line++; col = 1 } else col++
        return c
    }
    function ws() { while (i < text.length && " \t\r\n".includes(text[i])) next() }
    function describe(c) { return c === undefined ? "the end of the file" : JSON.stringify(c) }

    function value(path) {
        ws()
        const c = text[i]
        if (c === "{") return object(path)
        if (c === "[") return array(path)
        if (c === '"') return string()
        if (c === "-" || (c >= "0" && c <= "9")) return number()
        for (const [w, v] of [["true", true], ["false", false], ["null", null]]) {
            if (text.startsWith(w, i)) {
                for (let k = 0; k < w.length; k++) next()
                return v
            }
        }
        if (c === undefined) fail("unexpected end of the file, a value is missing")
        if (c === "'") fail("strings need double quotes (\"), not single quotes")
        fail("unexpected " + describe(c) + ", expected a value")
    }

    function object(path) {
        next()
        const o = {}
        ws()
        if (text[i] === "}") { next(); return o }
        let cl = 0, cc = 0                     // last comma, for "trailing comma"
        for (;;) {
            ws()
            if (text[i] === "}") fail("comma after the last entry (remove it)", cl, cc)
            if (text[i] === "'") fail("keys need double quotes (\"), not single quotes")
            if (text[i] !== '"') fail("expected a key in double quotes but found " + describe(text[i]))
            const kl = line, kc = col
            const k = string()
            if (Object.prototype.hasOwnProperty.call(o, k)) fail("\"" + k + "\" is in here twice", kl, kc)
            ws()
            if (text[i] !== ":") fail("expected : after \"" + k + "\" but found " + describe(text[i]))
            next()
            const p = path.concat(k)
            lines[JSON.stringify(p)] = kl
            o[k] = value(p)
            const el = line, ec = col          // end of the value, for "missing comma"
            ws()
            if (text[i] === ",") { cl = line; cc = col; next(); continue }
            if (text[i] === "}") { next(); return o }
            if (text[i] === '"') fail("missing comma after \"" + k + "\"", el, ec)
            fail("expected , or } after \"" + k + "\" but found " + describe(text[i]))
        }
    }

    function array(path) {
        next()
        const a = []
        ws()
        if (text[i] === "]") { next(); return a }
        let cl = 0, cc = 0
        for (;;) {
            ws()
            if (text[i] === "]") fail("comma after the last entry (remove it)", cl, cc)
            a.push(value(path.concat(a.length)))
            const el = line, ec = col
            ws()
            if (text[i] === ",") { cl = line; cc = col; next(); continue }
            if (text[i] === "]") { next(); return a }
            if (i < text.length && text[i] !== "}") fail("missing comma in the list", el, ec)
            fail("expected , or ] but found " + describe(text[i]))
        }
    }

    function string() {
        const sl = line, sc = col
        next()
        let s = ""
        for (;;) {
            const c = next()
            if (c === undefined) fail("string is never closed (missing \")", sl, sc)
            if (c === '"') return s
            if (c === "\n") fail("string is never closed (missing \" before the line break)", sl, sc)
            if (c !== "\\") { s += c; continue }
            const e = next()
            const map = { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" }
            if (e in map) s += map[e]
            else if (e === "u" && /^[0-9a-fA-F]{4}$/.test(text.substr(i, 4))) {
                s += String.fromCharCode(parseInt(text.substr(i, 4), 16))
                for (let k = 0; k < 4; k++) next()
            } else fail("invalid escape \\" + (e ?? ""))
        }
    }

    function number() {
        const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(text.substr(i, 64))
        if (!m) fail("invalid number")
        for (let k = 0; k < m[0].length; k++) next()
        return Number(m[0])
    }

    const v = value([])
    ws()
    if (i < text.length) fail("unexpected " + describe(text[i]) + " after the end of the data")
    return { value: v, lines: lines }
}
