.pragma library

// Mail helpers without QML (tests in tests/lib.test.mjs): conversations,
// day groups, reply / forward texts, addresses, the quick filter.

// "Re: AW: Fwd: Hello" → "Hello"
function baseSubject(s) {
    let t = String(s || "").trim()
    let prev
    do {
        prev = t
        t = t.replace(/^\s*((re|aw|antw|sv|vs|fw|fwd|wg|tr|rif|r)(\[\d+\])?\s*:\s*|\[[^\]]{1,40}\]\s*(?=(re|aw|fwd?|wg)\s*:))/i, "")
    } while (t !== prev)
    return t.trim()
}

function replySubject(s) { return "Re: " + baseSubject(s) }
function forwardSubject(s) { return "Fwd: " + baseSubject(s) }

// messages → conversations, newest first. Linked by Message-ID / References
// (In-Reply-To included); messages without any link stay on their own.
// [{ key, msgs (oldest first), latest, unread, flagged, attachments, subject, people }]
function threads(msgs) {
    const parent = {}
    const find = k => { while (parent[k] !== k) { parent[k] = parent[parent[k]]; k = parent[k] } return k }
    const union = (a, b) => {
        if (parent[a] === undefined) parent[a] = a
        if (parent[b] === undefined) parent[b] = b
        const ra = find(a), rb = find(b)
        if (ra !== rb) parent[rb] = ra
    }
    const keyOf = m => m.messageId || ("id:" + m.id)
    for (const m of msgs) {
        const k = keyOf(m)
        if (parent[k] === undefined) parent[k] = k
        for (const r of m.refs || []) union(r, k)
    }
    const groups = {}
    for (const m of msgs) {
        const root = find(keyOf(m))
        ;(groups[root] = groups[root] || []).push(m)
    }
    const out = []
    for (const k in groups) {
        const list = groups[k].slice().sort((a, b) => a.date - b.date)
        const last = list[list.length - 1]
        const people = []
        for (const m of list) {
            const n = displayName(m.from)
            if (n && !people.includes(n)) people.push(n)
        }
        out.push({
            key: k, msgs: list, latest: last.date, last: last,
            unread: list.filter(m => !m.seen).length,
            flagged: list.some(m => m.flagged),
            attachments: list.some(m => m.attachments > 0),
            subject: baseSubject(list[0].subject) || baseSubject(last.subject),
            people: people
        })
    }
    out.sort((a, b) => b.latest - a.latest)
    return out
}

// "Today" / "Yesterday" / weekday this week / "Last week" / "October" / "October 2025"
const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

function dayStart(t) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime() }

function dayGroup(t, now) {
    const today = dayStart(now)
    const day = dayStart(t)
    const diff = Math.round((today - day) / 86400000)
    if (diff <= 0) return "Today"
    if (diff === 1) return "Yesterday"
    const nd = new Date(now)
    const mondayOffset = (nd.getDay() + 6) % 7
    if (diff <= mondayOffset) return weekdays[new Date(t).getDay()]
    if (diff <= mondayOffset + 7) return "Last week"
    const d = new Date(t)
    return months[d.getMonth()] + (d.getFullYear() === nd.getFullYear() ? "" : " " + d.getFullYear())
}

function pad(n) { return (n < 10 ? "0" : "") + n }

// list column: 14:05 today, "Mon" this week, 3 Oct this year, 3.10.25 older
function shortDate(t, now) {
    if (!t) return ""
    const d = new Date(t), n = new Date(now)
    const diff = Math.round((dayStart(now) - dayStart(t)) / 86400000)
    if (diff <= 0) return pad(d.getHours()) + ":" + pad(d.getMinutes())
    if (diff < 7) return weekdays[d.getDay()].slice(0, 3)
    if (d.getFullYear() === n.getFullYear()) return d.getDate() + " " + months[d.getMonth()].slice(0, 3)
    return d.getDate() + "." + (d.getMonth() + 1) + "." + String(d.getFullYear()).slice(2)
}

function longDate(t) {
    const d = new Date(t)
    return weekdays[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear()
         + ", " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function displayName(a) {
    if (!a) return ""
    return (a.name || "").trim() || (a.email || "").split("@")[0]
}

function formatAddress(a) {
    if (!a || !a.email) return ""
    const n = (a.name || "").trim()
    if (!n) return a.email
    return (/[,;<>"@]/.test(n) ? "\"" + n.replace(/"/g, "") + "\"" : n) + " <" + a.email + ">"
}

const EMAIL = /^[^@\s<>,;"]+@[^@\s<>,;"]+\.[^@\s<>,;"]+$/

// "Lea <lea@x.org>, tom@x.org; \"Keller, Tom\" <t@k.ch>" → { list: [{name, email}], bad: ["…"] }
function parseAddresses(s) {
    const list = [], bad = []
    let cur = "", quoted = false, angle = false
    const parts = []
    for (const ch of String(s || "")) {
        if (ch === "\"") quoted = !quoted
        else if (ch === "<") angle = true
        else if (ch === ">") angle = false
        if ((ch === "," || ch === ";") && !quoted && !angle) { parts.push(cur); cur = "" } else cur += ch
    }
    parts.push(cur)
    for (let p of parts) {
        p = p.trim()
        if (!p) continue
        const m = /^(.*?)<\s*([^>]+?)\s*>\s*$/.exec(p)
        const a = m ? { name: m[1].trim().replace(/^"|"$/g, "").trim(), email: m[2] } : { name: "", email: p }
        if (EMAIL.test(a.email)) list.push(a); else bad.push(p)
    }
    return { list: list, bad: bad }
}

function sameAddress(a, b) { return String(a || "").trim().toLowerCase() === String(b || "").trim().toLowerCase() }

// who a reply goes to. mine: this account's addresses (not replied to)
function replyRecipients(m, mine, all) {
    const isMine = a => mine.some(x => sameAddress(x, a.email))
    let to = (m.replyTo && m.replyTo.length ? m.replyTo : [m.from]).filter(a => a && a.email)
    // replying to your own sent mail: to its recipients
    if (to.every(isMine) && m.to && m.to.length) to = m.to
    let cc = []
    if (all) {
        const seen = to.map(a => a.email.toLowerCase())
        for (const a of (m.to || []).concat(m.cc || [])) {
            const e = (a.email || "").toLowerCase()
            if (!e || isMine(a) || seen.includes(e)) continue
            seen.push(e)
            cc.push(a)
        }
    }
    return { to: to, cc: cc }
}

// "> " in front of every line, under "On <date>, <name> wrote:"
function quote(text, from, date) {
    const head = "On " + longDate(date) + ", " + (displayName(from) || "someone") + " wrote:"
    const body = String(text || "").replace(/\s+$/, "").split("\n").map(l => l.startsWith(">") ? ">" + l : "> " + l).join("\n")
    return head + "\n" + body
}

function forwardText(m, text) {
    const lines = ["-------- Forwarded message --------",
                   "Subject: " + (m.subject || ""),
                   "Date: " + longDate(m.date),
                   "From: " + formatAddress(m.from)]
    if (m.to && m.to.length) lines.push("To: " + m.to.map(formatAddress).join(", "))
    return lines.join("\n") + "\n\n" + String(text || "")
}

// plain text → HTML for the composer: links clickable, quoted lines ("> ") grey
function textToHtml(t) {
    const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    const link = s => s.replace(/\b(https?:\/\/[^\s<>"')\]]+)/g, '<a href="$1">$1</a>')
    return String(t || "").split("\n").map(l => {
        const h = link(esc(l)).replace(/ {2}/g, " &nbsp;")
        return /^\s*>/.test(l) ? '<span style="color:#7f7f7f">' + h + '</span>' : h
    }).join("<br>")
}

// a URL alone (pasted): becomes a link in the composer
function isUrl(t) { return /^\s*https?:\/\/[^\s<>"]+\s*$/.test(String(t || "")) }

// the quick filter. f: { unread, flagged, attachments, text }
function matches(m, f) {
    if (f.unread && m.seen) return false
    if (f.flagged && !m.flagged) return false
    if (f.attachments && !(m.attachments > 0)) return false
    const q = String(f.text || "").trim().toLowerCase()
    if (!q) return true
    const hay = [m.subject, m.from && m.from.name, m.from && m.from.email, m.preview,
                 (m.to || []).map(a => a.name + " " + a.email).join(" ")].join(" ").toLowerCase()
    return q.split(/\s+/).every(w => hay.includes(w))
}

// a stable color index for a sender (avatar circles)
function hue(s) {
    let h = 0
    for (const ch of String(s || "")) h = (h * 31 + ch.charCodeAt(0)) >>> 0
    return h % 8
}

function initials(a) {
    const n = displayName(a)
    const w = n.replace(/[^\p{L}\p{N} ]/gu, " ").trim().split(/\s+/).filter(x => x)
    if (w.length === 0) return "?"
    return (w[0][0] + (w.length > 1 ? w[w.length - 1][0] : "")).toUpperCase()
}

// collected addresses: newest use first, de-duplicated by address
// sent: these are people you wrote to (counted apart, they come first when completing)
function collect(book, addrs, now, sent) {
    const map = {}
    for (const a of book) map[a.email.toLowerCase()] = a
    for (const a of addrs) {
        if (!a || !EMAIL.test(a.email || "")) continue
        const k = a.email.toLowerCase()
        const old = map[k]
        map[k] = { name: a.name || (old ? old.name : ""), email: a.email, used: Math.max(now, old ? old.used : 0),
                   count: (old ? old.count : 0) + 1, sent: (old ? old.sent ?? 0 : 0) + (sent ? 1 : 0) }
    }
    return Object.values(map).sort((a, b) => b.used - a.used).slice(0, 2000)
}

// completions for what's being typed (the part after the last comma)
function complete(book, typed, limit) {
    const q = String(typed || "").split(/[,;]/).pop().trim().toLowerCase()
    if (q.length < 1) return []
    const hits = book.filter(a => a.email.toLowerCase().includes(q) || (a.name || "").toLowerCase().includes(q))
    // starts with it > people you wrote to > how often > how recently
    const score = a => (a.sent ?? 0) * 3 + a.count
    hits.sort((a, b) => {
        const sa = a.email.toLowerCase().startsWith(q) || (a.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q))
        const sb = b.email.toLowerCase().startsWith(q) || (b.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q))
        return (sb - sa) || (((b.sent ?? 0) > 0) - ((a.sent ?? 0) > 0)) || (score(b) - score(a)) || (b.used - a.used)
    })
    return hits.slice(0, limit || 6)
}

// replace the part being typed with a picked address
function insertAddress(text, a) {
    const parts = String(text || "").split(/([,;])/)
    parts[parts.length - 1] = (parts.length > 1 ? " " : "") + formatAddress(a)
    return parts.join("") + ", "
}

// mailto:a@b.c?subject=…&cc=…&body=… → { to, cc, bcc, subject, body } (other keys ignored)
function parseMailto(url) {
    const dec = s => { try { return decodeURIComponent(s) } catch (e) { return s } }
    const s = String(url || "").replace(/^mailto:/i, "")
    const q = s.indexOf("?")
    const out = { to: dec(q < 0 ? s : s.slice(0, q)), cc: "", bcc: "", subject: "", body: "" }
    if (q >= 0)
        for (const kv of s.slice(q + 1).split("&")) {
            const i = kv.indexOf("=")
            const k = dec((i < 0 ? kv : kv.slice(0, i)).replace(/\+/g, " ")).toLowerCase()
            const v = i < 0 ? "" : dec(kv.slice(i + 1).replace(/\+/g, "%20"))
            if (!(k in out)) continue
            out[k] = k === "to" ? [out.to, v].filter(x => x).join(", ") : v
        }
    // one line only where a line break would mean a new header
    for (const k of ["to", "cc", "bcc", "subject"]) out[k] = out[k].replace(/[\r\n]+/g, " ").trim()
    return out
}

// "anbei" / "attached" in what you wrote (not in the quoted part) but nothing attached
function mentionsAttachment(text) {
    const own = String(text || "").split("\n").filter(l => !/^\s*>/.test(l)).join("\n").split(/\n-- \n/)[0]
    return /\b(attach(ed|ment|ments)?|enclosed|anbei|angehängt|anhang|beigefügt|im anhang|pièces? jointes?|adjunto|allegat[oi])\b/i.test(own)
}

// ── Links ──
// &amp; &lt; &#39; &#x2F; … → the characters
function decodeEntities(s) {
    const named = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " }
    return String(s || "").replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) =>
        e[0] === "#" ? String.fromCodePoint(parseInt(e[1] === "x" || e[1] === "X" ? e.slice(2) : e.slice(1), e[1] === "x" || e[1] === "X" ? 16 : 10))
                     : named[e.toLowerCase()] ?? m)
}
// a message's links: href → the texts shown for it (to compare what a link says with where it goes)
function anchorTexts(html) {
    const out = {}
    const re = /<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)<\/a>/gi
    let m
    while ((m = re.exec(String(html || "")))) {
        const href = decodeEntities(m[1] ?? m[2]).trim()
        const text = decodeEntities(m[3].replace(/<[^>]*>/g, "")).replace(/\s+/g, " ").trim()
        if (text) (out[href] = out[href] || []).push(text)
    }
    return out
}
// the host of a URL: lowercase, without user / port ("" when it has none)
function urlHost(u) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]*)/i.exec(String(u || "").trim())
    return m ? m[1].replace(/^.*@/, "").replace(/:\d+$/, "").replace(/^\[|\]$/g, "").toLowerCase() : ""
}
// the site a host belongs to, roughly: mail.google.com → google.com, shop.example.co.uk → example.co.uk
function siteOf(host) {
    const p = String(host || "").toLowerCase().replace(/^www\./, "").split(".").filter(x => x)
    if (p.length <= 2 || /^\d+$/.test(p[p.length - 1])) return p.join(".")
    const n = p[p.length - 1].length === 2 && ["co", "com", "org", "net", "ac", "gov", "edu"].includes(p[p.length - 2]) ? 3 : 2
    return p.slice(-n).join(".")
}
// the site a link's text claims ("paypal.com", "https://www.paypal.com/x"), else ""
function claimedHost(text) {
    const t = String(text || "").trim().replace(/^<|>$/g, "")
    const m = /^(?:https?:\/\/)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?::\d+)?(?:[\/?#]\S*)?$/i.exec(t)
    return m ? m[1].toLowerCase().replace(/^www\./, "") : ""
}
// the hovered / clicked link: { url, scheme, host, site, warn } — warn: why it looks
// like a trick ("" when it doesn't). texts: what the message shows for it (anchorTexts)
function linkCheck(url, texts) {
    const u = String(url || "").trim()
    const scheme = (/^([a-z][a-z0-9+.-]*):/i.exec(u)?.[1] ?? "").toLowerCase()
    const host = urlHost(u)
    const site = siteOf(host)
    let warn = ""
    if (scheme && !["http", "https", "mailto", "tel"].includes(scheme))
        warn = "Opens a " + scheme + ": link, not a web page"
    else if (scheme === "http" || scheme === "https") {
        if (/^[a-z]+:\/\/[^\/?#]*@/i.test(u)) warn = "The part before the @ is a disguise, it goes to " + host
        else if (/^\d+(\.\d+){3}$/.test(host) || host.includes(":")) warn = "Goes to a bare IP address, not a named site"
        else if (/(^|\.)xn--/.test(host)) warn = "The address is written with look-alike letters (" + host + ")"
        else for (const t of texts || []) {
            const c = claimedHost(t)
            if (c && siteOf(c) !== site) { warn = "The text says " + c + ", but it goes to " + site; break }
        }
    }
    return { url: u, scheme: scheme, host: host, site: site, warn: warn }
}

// ── Dates in a message (for "Add to calendar") ──
const MONTHS = { jan: 0, januar: 0, january: 0, feb: 1, februar: 1, february: 1, mär: 2, märz: 2, maerz: 2, mar: 2, march: 2,
                 apr: 3, april: 3, mai: 4, may: 4, jun: 5, juni: 5, june: 5, jul: 6, juli: 6, july: 6,
                 aug: 7, august: 7, sep: 8, sept: 8, september: 8, okt: 9, oktober: 9, oct: 9, october: 9,
                 nov: 10, november: 10, dez: 11, dezember: 11, dec: 11, december: 11 }
// dates (with a time when one follows) in a message's text, from today on, at most `max`:
// [{ start, end, allDay, at, len }] (ms; at / len: where in the text, the time included;
// all: every one, the same date again too, no limit). 12.11.2026, 12.11., 2026-11-12,
// 12. November (2026), November 12(, 2026), 12 November 2026 — then "14:00", "um 14 Uhr",
// "2 pm", "14:00–15:30". Quoted lines (> …) are skipped.
function findDates(text, now, max, all) {
    const t = String(text || "").split("\n").map(l => /^\s*>/.test(l) ? " ".repeat(l.length) : l).join("\n")
    const today = new Date(now); today.setHours(0, 0, 0, 0)
    const mon = "([a-zäA-ZÄ]{3,9})\\.?"
    const pats = [
        { re: /\b(\d{4})-(\d{2})-(\d{2})\b/g, f: m => [+m[1], +m[2] - 1, +m[3]] },
        { re: /\b(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?(?!\d)/g, f: m => [m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : 0, +m[2] - 1, +m[1]] },
        { re: new RegExp("\\b(\\d{1,2})\\.?\\s+" + mon + "(?:\\s+(\\d{4}))?", "g"), f: m => [m[3] ? +m[3] : 0, MONTHS[m[2].toLowerCase()], +m[1]] },
        { re: new RegExp("\\b" + mon + "\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b", "g"), f: m => [m[3] ? +m[3] : 0, MONTHS[m[1].toLowerCase()], +m[2]] }
    ]
    const found = []
    for (const p of pats) {
        p.re.lastIndex = 0
        let m
        while ((m = p.re.exec(t))) {
            let [y, mo, d] = p.f(m)
            if (mo === undefined || mo < 0 || mo > 11 || d < 1 || d > 31) continue
            if (found.some(x => m.index < x.at + x.len && x.at < m.index + m[0].length)) continue   // another pattern's
            let date = new Date(y || today.getFullYear(), mo, d)
            if (date.getMonth() !== mo) continue                     // 31.02.
            if (!y && date < today) date = new Date(today.getFullYear() + 1, mo, d)
            if (date < today || date.getFullYear() > today.getFullYear() + 2) continue
            // a time right after it ("12.11. um 14:00", "Nov 12 at 2 pm", "14:00 – 15:30")
            const after = t.slice(m.index + m[0].length, m.index + m[0].length + 40)
            const tm = /^[^\S\n]*(?:,|um|ab|at|from|von|,?\s*\w{0,3}\.?)?[^\S\n]*(\d{1,2})(?:[:.](\d{2}))?[^\S\n]*(uhr|h\b|am|pm)?(?:[^\S\n]*(?:-|–|bis|to)[^\S\n]*(\d{1,2})(?:[:.](\d{2}))?[^\S\n]*(uhr|h\b|am|pm)?)?/i.exec(after)
            const hourOf = (h, ap) => { h = +h; if (/pm/i.test(ap || "") && h < 12) h += 12; if (/am/i.test(ap || "") && h === 12) h = 0; return h }
            let start = date.getTime(), end = 0, allDay = true, len = m[0].length
            if (tm && (tm[2] !== undefined || tm[3]) && +tm[1] < 24 && +(tm[2] || 0) < 60) {
                len += tm[0].replace(/\s+$/, "").length
                const s = new Date(date); s.setHours(hourOf(tm[1], tm[3] || tm[6]), +(tm[2] || 0), 0, 0)
                start = s.getTime(); allDay = false
                if (tm[4] !== undefined && +tm[4] < 24) {
                    const e = new Date(date); e.setHours(hourOf(tm[4], tm[6]), +(tm[5] || 0), 0, 0)
                    if (e > s) end = e.getTime()
                }
            }
            found.push({ start: start, end: end, allDay: allDay, at: m.index, len: len })
        }
    }
    found.sort((a, b) => a.at - b.at)
    if (all) return found
    const out = []
    for (const f of found)
        if (!out.some(o => o.start === f.start)) out.push(f)
    return out.slice(0, max || 3)
}

// the dates in a message's HTML as links (qsdate:start-end-allDay), so a click on one makes a
// calendar event; text inside links / <style> stays as it is. style: the links' CSS,
// mark: HTML after the date inside the link (an icon)
function linkDates(html, now, style, mark) {
    let inLink = 0, skip = 0
    return String(html || "").split(/(<[^>]*>)/).map(seg => {
        if (seg.startsWith("<")) {
            if (/^<a\b/i.test(seg)) inLink++
            else if (/^<\/a\s*>/i.test(seg)) inLink = Math.max(0, inLink - 1)
            else if (/^<(style|script|title)\b/i.test(seg)) skip++
            else if (/^<\/(style|script|title)\s*>/i.test(seg)) skip = Math.max(0, skip - 1)
            return seg
        }
        if (inLink || skip || !/\d/.test(seg)) return seg
        // entities (&nbsp; …) as spaces of their length: the positions stay the same
        const ds = findDates(seg.replace(/&[a-z0-9#]+;/gi, e => " ".repeat(e.length)), now, 0, true)
        let out = "", pos = 0
        for (const d of ds) {
            if (d.at < pos) continue
            out += seg.slice(pos, d.at) + '<a href="qsdate:' + d.start + "-" + d.end + "-" + (d.allDay ? 1 : 0) + '"'
                 + (style ? ' style="' + style + '"' : "") + ">" + seg.slice(d.at, d.at + d.len) + (mark || "") + "</a>"
            pos = d.at + d.len
        }
        return out + seg.slice(pos)
    }).join("")
}
// qsdate:start-end-allDay → { start, end, allDay } (null: not one)
function parseDateLink(url) {
    const m = /^qsdate:(\d+)-(\d+)-([01])$/.exec(String(url || ""))
    return m ? { start: +m[1], end: +m[2], allDay: m[3] === "1" } : null
}
