.pragma library

// The address bar (Ctrl+L): what was typed → a path, and completions.
//   resolve(text, here, home)   an absolute path, or "" (empty, or a URI we can't open yet)
//       "/a", "~", "~/a", "file:///a%20b", or relative to the open folder ("a/b", "..")
//   split(text)                 { dir, part }: the typed text up to the last "/" and what follows
//                               ("~/Doc" → { dir: "~/", part: "Doc" })
//   matches(names, part, max)   folder names for `part`: starting with it first, then
//                               containing it (both ignoring case); hidden ones only for a "."
//   common(names)               the longest start they share (Tab completes to it)
// Mounted servers (GVfs: [{ uri: "smb://srv/share/", path: "/run/user/…/gvfs/smb-share:…" }]):
//   mountOf(path, mounts)       the server mount a local path is in (the deepest), or null
//   toServer(path, mounts)      that path as its server address ("smb://srv/share/dir"), or ""
//   fromServer(text, mounts)    a typed address inside a mounted server → its local path, or ""
//   encodeUri(text)             a typed address with each path part percent-encoded (once)
//   withUser(uri, user, domain) the address for that user ("" takes the user out):
//                               sftp://user@host/…, smb://DOMAIN;user@host/share (what GVfs reads)
//   userOf(uri)                 { user, domain } named in an address ("" when none)
// Saved servers ([{ uri, name }]):
//   serverOffers(text, servers) those matching what's typed: [{ server, continues }]. A typed
//                               scheme is kept: "ssh://srv" never offers smb://srv (only ssh /
//                               sftp, one family: GVfs names ssh that way); the scheme alone
//                               ("smb://") lists all of its servers. `continues`: Enter may go
//                               there by itself, i.e. it's what's typed, carried on; not once a
//                               whole host is typed and only a share / folder would be added
//   hasExact(names, part)       `part` is one of the folder names in full (Enter means that one)

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

function _scheme(u) { const m = /^([a-z][a-z0-9+.-]*):\/\//i.exec(u); return m ? m[1].toLowerCase() : "" }
function _family(s) { return s === "ssh" ? "sftp" : s }
function _bare(u) { return u.toLowerCase().replace(/^[a-z][a-z0-9+.-]*:\/\//, "") }

function serverOffers(text, servers) {
    const low = String(text).trim().toLowerCase()
    const out = []
    if (low.length < 2) return out
    const sc = _scheme(low), q = _bare(low)
    for (const sv of Array.isArray(servers) ? servers : []) {
        if (!sv || typeof sv.uri !== "string") continue
        const uri = sv.uri.toLowerCase(), name = String(sv.name ?? "").toLowerCase(), host = _bare(uri)
        if (sc === "") {
            // a name or a part of the address: a search, the best one may be picked
            if (uri.includes(low) || name.includes(low)) out.push({ server: sv, continues: true })
            continue
        }
        if (_family(_scheme(uri)) !== _family(sc)) continue
        if (q === "") { out.push({ server: sv, continues: false }); continue }
        if (!host.includes(q) && !name.includes(q)) continue
        out.push({ server: sv, continues: host.startsWith(q) && !host.slice(q.length).startsWith("/") })
    }
    // those carrying on what's typed first
    return out.filter(o => o.continues).concat(out.filter(o => !o.continues))
}

function hasExact(names, part) {
    return part !== "" && (Array.isArray(names) ? names : []).indexOf(part) >= 0
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

function _dec(s) { try { return decodeURIComponent(s) } catch (e) { return s } }
function _isServer(m) { return !!m && typeof m.uri === "string" && typeof m.path === "string" && m.path.startsWith("/")
                               && /^[a-z][a-z0-9+.-]*:\/\//i.test(m.uri) && !/^file:/i.test(m.uri) }

function mountOf(path, mounts) {
    let best = null
    for (const m of Array.isArray(mounts) ? mounts : []) {
        if (!_isServer(m)) continue
        const root = m.path.replace(/\/+$/, "")
        if ((path === root || path.startsWith(root + "/")) && (!best || root.length > best.path.replace(/\/+$/, "").length)) best = m
    }
    return best
}

function toServer(path, mounts) {
    const m = mountOf(path, mounts)
    if (!m) return ""
    return _dec(m.uri.replace(/\/+$/, "")) + path.slice(m.path.replace(/\/+$/, "").length)
}

function fromServer(text, mounts) {
    const t = String(text).trim().replace(/\/+$/, "")
    if (t.indexOf("\0") >= 0) return ""
    const low = _dec(t).toLowerCase()
    let best = ""
    for (const m of Array.isArray(mounts) ? mounts : []) {
        if (!_isServer(m)) continue
        const base = _dec(m.uri.replace(/\/+$/, ""))
        const b = base.toLowerCase()
        if (low !== b && !low.startsWith(b + "/")) continue
        const parts = _dec(t).slice(base.length).split("/").filter(x => x !== "" && x !== ".")
        if (parts.some(x => x === "..")) return ""
        const p = m.path.replace(/\/+$/, "") + (parts.length ? "/" + parts.join("/") : "")
        if (p.length > best.length) best = p
    }
    return best
}

function encodeUri(text) {
    const t = String(text).trim()
    const m = /^([a-z][a-z0-9+.-]*:\/\/[^/]*)(.*)$/i.exec(t)
    if (!m) return t
    return m[1] + m[2].split("/").map(x => encodeURIComponent(_dec(x))).join("/")
}

function withUser(uri, user, domain) {
    const m = /^([a-z][a-z0-9+.-]*):\/\/([^\/]*)(.*)$/i.exec(String(uri).trim())
    if (!m) return String(uri)
    const host = m[2].slice(m[2].lastIndexOf("@") + 1)
    const u = String(user ?? "").trim(), d = String(domain ?? "").trim()
    if (u === "") return m[1] + "://" + host + m[3]
    const who = (m[1].toLowerCase() === "smb" && d !== "" ? encodeURIComponent(d) + ";" : "") + encodeURIComponent(u)
    return m[1] + "://" + who + "@" + host + m[3]
}

function userOf(uri) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/([^\/]*)@/i.exec(String(uri).trim())
    if (!m) return { user: "", domain: "" }
    const who = m[1].split(":")[0], semi = who.indexOf(";")
    return { user: _dec(semi >= 0 ? who.slice(semi + 1) : who), domain: semi >= 0 ? _dec(who.slice(0, semi)) : "" }
}
