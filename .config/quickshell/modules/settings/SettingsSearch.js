.pragma library

// Search for the settings app: scoring, synonyms, typo tolerance, highlight.
//
// An entry: { label, desc, keywords, section, page }  (strings)
// score(entry, query) → number (higher = better), or -1 if it doesn't match.
// Every word of the query has to match somewhere (any order), each by the
// best of: whole word > start of a word > inside a word > a synonym > a
// typo (1 edit, 2 for long words). The label counts most, then keywords,
// then page / section, then the description.

// words that mean the same thing here (each group is one meaning)
const synonymGroups = [
    ["transparency", "transparent", "opacity", "opaque", "alpha", "see-through"],
    ["gap", "gaps", "spacing", "space", "padding", "margin", "distance"],
    ["radius", "round", "rounded", "rounding", "corner", "corners"],
    ["color", "colour", "colors", "tint", "accent", "theme", "pywal"],
    ["font", "typeface", "text", "letters"],
    ["size", "big", "bigger", "small", "smaller", "scale"],
    ["wallpaper", "background", "backdrop"],
    ["monitor", "monitors", "display", "displays", "screen", "screens", "output", "outputs"],
    ["resolution", "mode", "pixels"],
    ["refresh", "hz", "hertz", "framerate", "fps"],
    ["rotate", "rotation", "transform", "portrait", "landscape", "flip"],
    ["keybind", "keybinds", "shortcut", "shortcuts", "hotkey", "hotkeys", "binding", "bindings", "bind", "binds", "keys"],
    ["autostart", "startup", "start", "login", "boot", "launch", "exec"],
    ["dns", "nameserver", "nameservers", "resolver", "resolve", "lookup", "nslookup", "dig"],
    ["ip", "address", "addresses", "ipv4", "ipv6"],
    ["static", "manual", "fixed"],
    ["dhcp", "lease", "automatic"],
    ["wifi", "wi-fi", "wireless", "wlan", "ssid", "hotspot"],
    ["ethernet", "lan", "wired", "cable", "nic", "interface", "interfaces", "adapter", "eth"],
    ["vpn", "wireguard", "openvpn", "ovpn", "tunnel"],
    ["hosts", "hostfile", "redirect", "remap", "block"],
    ["hostname", "computername", "machine"],
    ["blur", "blurry", "frosted", "glass"],
    ["shadow", "shadows", "drop"],
    ["border", "outline", "ring", "frame"],
    ["animation", "animations", "motion", "transition", "transitions", "slowdown"],
    ["keyboard", "layout", "xkb", "numlock", "qwertz", "qwerty"],
    ["mouse", "pointer", "cursor", "touchpad", "trackpad", "sensitivity", "acceleration", "accel"],
    ["notification", "notifications", "popup", "popups", "toast", "alert", "alerts"],
    ["battery", "power", "charging", "charge", "low"],
    ["calendar", "event", "events", "reminder", "reminders", "sync", "caldav"],
    ["picture", "avatar", "photo", "image", "face", "profile"],
    ["name", "username", "user", "greeting"],
    ["export", "backup", "save", "transfer"],
    ["import", "restore", "load"],
    ["hover", "zoom", "grow"],
    ["press", "click", "shrink"],
    ["bar", "panel", "topbar", "statusbar", "waybar"],
    ["window", "windows", "app", "apps", "application", "applications"],
    ["workspace", "workspaces", "desktop", "desktops"],
    ["tiling", "tile", "tiled", "column", "columns"],
    ["delete", "remove", "clear"],
    ["password", "passphrase", "key", "psk"],
    ["route", "routes", "routing", "gateway"],
    ["template", "templates", "syntax", "words", "kdl", "lua"]
]

const synonyms = (() => {
    const m = {}
    for (const g of synonymGroups) for (const w of g) m[w] = (m[w] ?? []).concat(g.filter(x => x !== w))
    return m
})()

function words(s) {
    return String(s ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .split(/[^a-z0-9#@.+-]+/)
        // each word, its parts ("wi-fi" → wi, fi, wi-fi); no Array.flatMap in Qt's JS engine
        .reduce((out, w) => out.concat(w.split(/[.+-]/), w.includes("-") || w.includes(".") ? [w] : []), [])
        .filter(w => w !== "")
}

// edit distance with transpositions, stops early above `max`
function distance(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1
    const d = []
    for (let i = 0; i <= a.length; i++) { d[i] = [i]; }
    for (let j = 0; j <= b.length; j++) d[0][j] = j
    for (let i = 1; i <= a.length; i++) {
        let rowMin = Infinity
        for (let j = 1; j <= b.length; j++) {
            const cost = a[i - 1] === b[j - 1] ? 0 : 1
            d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1)
            rowMin = Math.min(rowMin, d[i][j])
        }
        if (rowMin > max) return max + 1
    }
    return d[a.length][b.length]
}

// how well one query word matches a list of words (0 = not at all)
function wordMatch(token, ws) {
    let best = 0
    const syn = synonyms[token] ?? []
    const typos = token.length >= 7 ? 2 : token.length >= 4 ? 1 : 0
    for (const w of ws) {
        if (w === token) return 1
        // one letter only counts as a whole word ("super r": the key R, not "right")
        if (token.length >= 2 && w.startsWith(token)) best = Math.max(best, 0.85)
        else if (token.length >= 3 && w.includes(token)) best = Math.max(best, 0.55)
        if (syn.includes(w)) best = Math.max(best, 0.7)
        else if (token.length >= 3 && syn.some(s => w.startsWith(s) && s.length >= 3)) best = Math.max(best, 0.6)
        if (typos > 0 && best < 0.45 && w.length >= 3 && distance(token, w, typos) <= typos) best = Math.max(best, 0.45)
        // the typo'd word might be the start of a longer one ("monit" ← "montr")
        if (typos > 0 && best < 0.4 && w.length > token.length && distance(token, w.slice(0, token.length), 1) <= 1) best = Math.max(best, 0.4)
    }
    return best
}

const weights = { label: 10, keywords: 7, page: 4, section: 4, desc: 2.5 }

// prepare an entry once (words of each field)
function prepare(entry) {
    entry._w = {}
    for (const f of Object.keys(weights)) entry._w[f] = words(entry[f])
    entry._label = String(entry.label ?? "").toLowerCase()
    return entry
}

function tokens(query) { return words(query).filter((w, i, all) => all.indexOf(w) === i) }

function score(entry, query, toks) {
    toks = toks ?? tokens(query)
    if (toks.length === 0) return -1
    if (!entry._w) prepare(entry)
    let total = 0
    for (const t of toks) {
        let best = 0
        for (const f of Object.keys(weights)) {
            const m = wordMatch(t, entry._w[f])
            if (m > 0) best = Math.max(best, m * weights[f])
        }
        if (best === 0) return -1
        total += best
    }
    // the whole query in the label, or the label starting with it: top
    const q = String(query).trim().toLowerCase()
    if (q.length >= 2 && entry._label.includes(q)) total += entry._label.startsWith(q) ? 12 : 7
    return total + (entry.boost ?? 0)
}

// closest known word to each query word ("Did you mean …"), or ""
function suggest(query, vocabulary) {
    const toks = tokens(query)
    let changed = false
    const out = toks.map(t => {
        if (vocabulary.has(t) || synonyms[t]) return t
        let best = t, bestD = 3
        for (const v of vocabulary) {
            if (Math.abs(v.length - t.length) > 2) continue
            const d = distance(t, v, 2)
            if (d < bestD) { bestD = d; best = v }
        }
        if (best !== t) changed = true
        return best
    })
    return changed ? out.join(" ") : ""
}

function vocabularyOf(entries) {
    const v = new Set()
    for (const e of entries) {
        if (!e._w) prepare(e)
        for (const f of Object.keys(weights)) for (const w of e._w[f]) if (w.length >= 3) v.add(w)
    }
    return v
}

// the label with the matched parts highlighted (rich text)
function highlight(text, query, color) {
    const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    const toks = tokens(query).filter(t => t.length >= 1)
    if (toks.length === 0) return esc(text)
    const lower = text.toLowerCase()
    const mark = new Array(text.length).fill(false)
    for (const t of toks) {
        const alts = [t].concat(synonyms[t] ?? [])
        for (const a of alts) {
            if (a.length < 2 && a !== t) continue
            // word starts first, then anywhere
            // a single letter only as a whole word (the key R, not the r of "Reset")
            const re = new RegExp("(^|[^a-z0-9])(" + a.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")" + (a.length === 1 ? "(?![a-z0-9])" : ""), "g")
            let m
            while ((m = re.exec(lower)) !== null) {
                const s = m.index + m[1].length
                for (let i = s; i < s + m[2].length; i++) mark[i] = true
                if (re.lastIndex === m.index) re.lastIndex++
            }
        }
    }
    let out = "", on = false
    for (let i = 0; i < text.length; i++) {
        // (StyledText: <font> and <b>, no <span style>)
        if (mark[i] !== on) { out += mark[i] ? "<font color=\"" + color + "\"><b>" : "</b></font>"; on = mark[i] }
        out += esc(text[i])
    }
    return out + (on ? "</b></font>" : "")
}
