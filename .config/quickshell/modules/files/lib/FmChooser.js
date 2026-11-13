.pragma library

// Another app's Open / Save dialog (the backend's "chooser" event, filesd/portal.py):
// what its file type filters let through, and what the dialog says.
//   pattern(glob)            a RegExp for one of a filter's globs ("*.png", "*.[jJ][pP][gG]"),
//                            the whole name, ignoring case; null when it matches everything
//   accepts(filter, item)    whether a filter { globs, mimes } shows an item { name, type, dir }
//                            (folders always show: you walk through them)
//   matcher(filter)          item => bool for a view, or null when everything shows
//   label(filter)            "Images (*.png, *.jpg)": its name, with its patterns when the name doesn't say
//   verb(req)                the accept button's text: the app's, else Open / Save / Select
//   title(req, prefix)       the window's title: `prefix` (FmSettings.dialogPrefix: what the
//                            compositor's rule for the dialogs matches) + the app's, else "Open a file" …
//   cleanName(text)          a typed file name: trimmed; "" when it can't be one (/, ., ..)

function pattern(glob) {
    const g = String(glob)
    if (g === "*" || g === "*.*" || g === "") return null
    let re = ""
    for (let i = 0; i < g.length; i++) {
        const c = g[i]
        // ([^] = any character, a line break in a name too; QML's engine has no "s" flag)
        if (c === "*") re += "[^]*"
        else if (c === "?") re += "[^]"
        else if (c === "[") {
            const end = g.indexOf("]", i + 2)
            if (end < 0) { re += "\\["; continue }
            let cls = g.slice(i + 1, end)
            if (cls[0] === "!") cls = "^" + cls.slice(1)
            re += "[" + cls.replace(/\\/g, "\\\\") + "]"
            i = end
        } else re += c.replace(/[.+^${}()|\\\]]/g, "\\$&")
    }
    try { return new RegExp("^" + re + "$", "i") } catch (e) { return /^$/ }
}

function _mime(rule, type) {
    if (rule === "*/*" || rule === "*") return true
    if (rule.endsWith("/*")) return type.startsWith(rule.slice(0, -1))
    return type === rule
}

function matcher(filter) {
    if (!filter) return null
    const globs = filter.globs ?? [], mimes = filter.mimes ?? []
    if (globs.length === 0 && mimes.length === 0) return null
    const res = []
    for (const g of globs) {
        const re = pattern(g)
        if (re === null) return null
        res.push(re)
    }
    if (mimes.some(m => m === "*/*" || m === "*")) return null
    return function (item) {
        if (item.dir) return true
        for (const re of res) if (re.test(item.name)) return true
        const type = item.type ?? ""
        for (const m of mimes) if (_mime(m, type)) return true
        return false
    }
}

function accepts(filter, item) {
    const f = matcher(filter)
    return f === null || f(item)
}

function label(filter) {
    const name = String(filter?.name ?? "").trim()
    const globs = (filter?.globs ?? []).slice(0, 4).join(", ") + ((filter?.globs ?? []).length > 4 ? ", …" : "")
    if (name === "") return globs || "All files"
    return /[*(]/.test(name) || globs === "" || globs === "*" ? name : name + " (" + globs + ")"
}

function verb(req) {
    const a = String(req?.accept ?? "").trim()
    if (a !== "") return a
    return req?.mode === "save" || req?.mode === "saveFiles" ? "Save" : req?.mode === "folder" ? "Select" : "Open"
}

function title(req, prefix) {
    let t = String(req?.title ?? "").trim()
    if (t === "") t = req?.mode === "save" ? "Save a file" : req?.mode === "saveFiles" ? "Save files to a folder"
                    : req?.mode === "folder" ? "Select a folder" : req?.multiple ? "Open files" : "Open a file"
    return (prefix ?? "") + t
}

function cleanName(text) {
    const n = String(text ?? "").trim()
    return n === "" || n === "." || n === ".." || n.indexOf("/") >= 0 || n.indexOf("\0") >= 0 ? "" : n
}
