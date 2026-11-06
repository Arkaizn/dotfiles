.pragma library

// The address bar (Ctrl+L): what was typed → a path, and completions.
//   resolve(text, here, home)   an absolute path, or "" (empty, or a URI we can't open yet)
//       "/a", "~", "~/a", "file:///a%20b", or relative to the open folder ("a/b", "..")
//   split(text)                 { dir, part }: the typed text up to the last "/" and what follows
//                               ("~/Doc" → { dir: "~/", part: "Doc" })
//   matches(names, part, max)   folder names for `part`: starting with it first, then
//                               containing it (both ignoring case); hidden ones only for a "."
//   common(names)               the longest start they share (Tab completes to it)

function resolve(text, here, home) {
    let t = String(text).trim()
    if (t === "") return ""
    if (t.indexOf("\0") >= 0) return ""
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(t)) {
        if (!t.startsWith("file://")) return ""
        let rest = t.slice(7)
        if (rest.startsWith("localhost/")) rest = rest.slice(9)
        if (!rest.startsWith("/")) return ""
        try { t = decodeURIComponent(rest) } catch (e) { return "" }
        if (t.indexOf("\0") >= 0) return ""
    } else if (t === "~" || t.startsWith("~/")) {
        t = home + t.slice(1)
    } else if (!t.startsWith("/")) {
        t = (here === "/" ? "" : here) + "/" + t
    }
    const out = []
    for (const part of t.split("/")) {
        if (part === "" || part === ".") continue
        if (part === "..") out.pop()
        else out.push(part)
    }
    return "/" + out.join("/")
}

function split(text) {
    const t = String(text)
    const i = t.lastIndexOf("/")
    return i < 0 ? { dir: "", part: t } : { dir: t.slice(0, i + 1), part: t.slice(i + 1) }
}

function matches(names, part, max) {
    const p = part.toLowerCase(), dot = part.startsWith(".")
    const start = [], inside = []
    for (const n of names) {
        if (n.startsWith(".") && !dot) continue
        const l = n.toLowerCase()
        if (l === p) continue                       // already typed in full
        if (l.startsWith(p)) start.push(n)
        else if (p !== "" && l.indexOf(p) >= 0) inside.push(n)
    }
    return start.concat(inside).slice(0, max || 8)
}

function common(names) {
    if (names.length === 0) return ""
    let c = names[0]
    for (const n of names) {
        let i = 0
        while (i < c.length && i < n.length && c[i].toLowerCase() === n[i].toLowerCase()) i++
        c = c.slice(0, i)
    }
    return c
}
