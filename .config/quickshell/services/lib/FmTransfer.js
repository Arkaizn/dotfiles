.pragma library

// The file manager's export file (Settings → Apps → Files → Export / Import):
// its preferences and what it keeps for you, nothing per device but the paths.
//
//   { "quickshellFiles": 1, "exported": "<ISO date>",
//     "settings":  { <Settings.files key>: value, … }           (FmSettings' spec)
//     "bookmarks": [{ uri, label }]                             (GTK's bookmarks: file:// and servers)
//     "groups":    [{ id, name, color, open }], "groupPins": { "<bookmark uri>": group id }
//     "servers":   [{ uri, name }]                              (saved servers, never a password)
//     "starred":   ["/path", …]
//     "views":     { sort, iconSize: { list, grid }, columns: […], sideOrder: […] } }
//
// Shared by the Settings app (reads / writes the file) and the file manager's
// process (hands over and takes in its part); pure, so tests run it in node.
//   PARTS · labels[part]
//   build(parts, src, now)        the export object; src: the same keys as the file
//   parse(text)                   { doc, error, problems }: a checked copy, bad entries left out
//   count(doc)                    { part: how many } for the parts in it
//   merge(cur, doc, parts, newId) what an import changes: { bookmarks (to add), groups, groupPins,
//                                 servers, starred, views } — added to what's there, nothing removed

var PARTS = ["settings", "bookmarks", "servers", "starred", "views"]
var labels = { settings: "Preferences", bookmarks: "Bookmarks and groups", servers: "Saved servers",
               starred: "Starred", views: "Views" }
var MAX = { bookmarks: 500, groups: 100, servers: 200, starred: 2000, list: 50 }
var SERVER = /^(smb|sftp|ssh|ftp|ftps|dav|davs|nfs|afp):\/\/\S+$/i

function obj(o) { return o !== null && typeof o === "object" && !Array.isArray(o) ? o : null }
function line(s, max) { return typeof s === "string" && s.length <= max && !/[\n\r\0]/.test(s) }
// an address as it may be kept: never a password (sftp://me:secret@host → sftp://me@host)
function safeUri(u) { return String(u).replace(/^([a-z][a-z0-9+.-]*:\/\/)([^@\/]*?):[^@\/]*@/i, "$1$2@") }
function bookmarkUri(u) { return line(u, 2048) && !/\s/.test(u) && (/^file:\/\/\//.test(u) || SERVER.test(u)) }

function names(a) { return Array.isArray(a) ? a.filter(function (x) { return typeof x === "string" && /^[A-Za-z0-9]{1,30}$/.test(x) }).slice(0, MAX.list) : undefined }

function build(parts, src, now) {
    var o = { quickshellFiles: 1, exported: now }
    if (parts.indexOf("settings") >= 0) o.settings = Object.assign({}, src.settings || {})
    if (parts.indexOf("bookmarks") >= 0) {
        o.bookmarks = (src.bookmarks || []).map(function (b) { return { uri: b.uri, label: b.label || "" } })
        o.groups = (src.groups || []).slice()
        o.groupPins = Object.assign({}, src.groupPins || {})
    }
    if (parts.indexOf("servers") >= 0) o.servers = (src.servers || []).map(function (s) { return { uri: safeUri(s.uri), name: s.name || "" } })
    if (parts.indexOf("starred") >= 0) o.starred = (src.starred || []).slice()
    if (parts.indexOf("views") >= 0) o.views = Object.assign({}, src.views || {})
    return o
}

function parse(text) {
    var raw = null
    try { raw = JSON.parse(text) } catch (e) { return { doc: null, error: "isn't valid JSON (" + e.message + ")", problems: [] } }
    if (!obj(raw) || raw.quickshellFiles !== 1)
        return { doc: null, error: "isn't a file manager export (no \"quickshellFiles\": 1)", problems: [] }
    var problems = [], doc = {}
    function bad(what) { if (problems.length < 20) problems.push(what) }

    if (raw.settings !== undefined) {
        if (obj(raw.settings)) {
            doc.settings = {}
            // (checked against the spec by the caller: FmSettings.check)
            for (var k in raw.settings) if (/^[A-Za-z0-9]{1,40}$/.test(k)) doc.settings[k] = raw.settings[k]; else bad("setting " + JSON.stringify(k).slice(0, 40))
        } else bad("settings: not an object")
    }
    if (raw.bookmarks !== undefined) {
        doc.bookmarks = []
        var seen = {}
        ;(Array.isArray(raw.bookmarks) ? raw.bookmarks : []).slice(0, MAX.bookmarks).forEach(function (b, i) {
            if (!obj(b) || !bookmarkUri(b.uri) || (b.label !== undefined && !line(b.label, 500))) { bad("bookmark " + (i + 1)); return }
            if (seen[b.uri]) return
            seen[b.uri] = true
            doc.bookmarks.push({ uri: b.uri, label: (b.label || "").trim() })
        })
        doc.groups = []
        var ids = {}
        ;(Array.isArray(raw.groups) ? raw.groups : []).slice(0, MAX.groups).forEach(function (g, i) {
            if (!obj(g) || !/^[A-Za-z0-9_-]{1,40}$/.test(g.id) || !line(g.name, 200) || g.name.trim() === "" || ids[g.id]) { bad("group " + (i + 1)); return }
            ids[g.id] = true
            doc.groups.push({ id: g.id, name: g.name.trim(), color: /^[A-Za-z0-9]{1,30}$/.test(g.color) ? g.color : "blue", open: g.open !== false })
        })
        doc.groupPins = {}
        var pins = obj(raw.groupPins) || {}
        for (var u in pins) if (seen[u] && ids[pins[u]]) doc.groupPins[u] = pins[u]
    }
    if (raw.servers !== undefined) {
        doc.servers = []
        ;(Array.isArray(raw.servers) ? raw.servers : []).slice(0, MAX.servers).forEach(function (s, i) {
            if (!obj(s) || !line(s.uri, 2048) || !SERVER.test(s.uri) || (s.name !== undefined && !line(s.name, 200))) { bad("server " + (i + 1)); return }
            var uri = safeUri(s.uri)
            if (!doc.servers.some(function (x) { return x.uri === uri })) doc.servers.push({ uri: uri, name: (s.name || "").trim() })
        })
    }
    if (raw.starred !== undefined) {
        doc.starred = []
        ;(Array.isArray(raw.starred) ? raw.starred : []).slice(0, MAX.starred).forEach(function (p, i) {
            if (!line(p, 4096) || p.charAt(0) !== "/" || /(^|\/)\.\.(\/|$)/.test(p)) { bad("starred " + (i + 1)); return }
            if (doc.starred.indexOf(p) < 0) doc.starred.push(p)
        })
    }
    if (raw.views !== undefined) {
        var v = obj(raw.views)
        if (v) {
            // shapes only: the file manager clamps the values (FmViews, FmZoom, FmColumns)
            doc.views = {}
            if (obj(v.sort)) doc.views.sort = v.sort
            if (obj(v.iconSize)) doc.views.iconSize = { list: v.iconSize.list, grid: v.iconSize.grid }
            if (names(v.columns)) doc.views.columns = names(v.columns)
            if (names(v.sideOrder)) doc.views.sideOrder = names(v.sideOrder)
        } else bad("views: not an object")
    }
    return { doc: doc, error: "", problems: problems }
}

function count(doc) {
    var c = {}
    if (doc.settings) c.settings = Object.keys(doc.settings).length
    if (doc.bookmarks) c.bookmarks = doc.bookmarks.length
    if (doc.servers) c.servers = doc.servers.length
    if (doc.starred) c.starred = doc.starred.length
    if (doc.views) c.views = Object.keys(doc.views).length
    return c
}

// cur: { bookmarks: [{ uri }], groups, groupPins, servers, starred }. Groups match by name (the
// file's id → the one here), new ones get newId(i); a bookmark already in a group stays there.
function merge(cur, doc, parts, newId) {
    var out = {}
    var has = function (p) { return parts.indexOf(p) >= 0 && doc[p] !== undefined }
    if (has("bookmarks")) {
        var known = {}
        cur.bookmarks.forEach(function (b) { known[b.uri] = true })
        out.bookmarks = doc.bookmarks.filter(function (b) { return !known[b.uri] })
        var groups = cur.groups.slice(), map = {}, made = 0
        doc.groups.forEach(function (g) {
            var same = groups.filter(function (x) { return x.name === g.name })[0]
            if (same) { map[g.id] = same.id; return }
            var id = newId(made++)
            map[g.id] = id
            groups.push({ id: id, name: g.name, color: g.color, open: g.open })
        })
        var pins = Object.assign({}, cur.groupPins)
        for (var u in doc.groupPins) if (pins[u] === undefined && map[doc.groupPins[u]]) pins[u] = map[doc.groupPins[u]]
        out.groups = groups
        out.groupPins = pins
    }
    if (has("servers")) {
        var list = cur.servers.slice()
        doc.servers.forEach(function (s) { if (!list.some(function (x) { return x.uri === s.uri })) list.push({ uri: s.uri, name: s.name || s.uri.replace(/^[a-z]+:\/\//i, "") }) })
        out.servers = list.slice(-50)
    }
    if (has("starred")) {
        var st = cur.starred.slice()
        doc.starred.forEach(function (p) { if (st.indexOf(p) < 0) st.push(p) })
        out.starred = st.slice(-1000)
    }
    if (has("views")) out.views = doc.views
    return out
}
