.pragma library

// Input checks for anything handed to network tools (ping, traceroute, nc,
// ssh, …). Each returns "" when fine, otherwise what's wrong. A leading "-"
// is always refused, so a value can never be read as an option.

function ipv4(s) {
    const p = s.split(".")
    return p.length === 4 && p.every(o => /^\d{1,3}$/.test(o) && Number(o) <= 255)
}

function ipv6(s) {
    if (!/^[0-9a-fA-F:]+$/.test(s) || !s.includes(":")) return false
    if (s.split("::").length > 2) return false
    const g = s.split(":").filter(x => x !== "")
    return g.every(x => x.length <= 4) && (s.includes("::") ? g.length < 8 : g.length === 8)
}

// a host name (RFC 1123 labels), IPv4 or IPv6
function host(s) {
    s = String(s ?? "").trim()
    if (s === "") return "enter a host"
    if (s.startsWith("-")) return "can't start with \"-\""
    if (ipv4(s) || ipv6(s)) return ""
    if (s.length > 253) return "too long"
    const labels = s.replace(/\.$/, "").split(".")
    // all-digit last label = a broken IPv4 address (256.1.1.1), not a name
    if (labels.length > 1 && /^\d+$/.test(labels[labels.length - 1])) return "not a valid IP address"
    if (labels.every(l => /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(l))) return ""
    return "not a host name or IP address"
}

function port(s) {
    s = String(s ?? "").trim()
    if (!/^\d{1,5}$/.test(s)) return "a number 1–65535"
    const n = Number(s)
    return n >= 1 && n <= 65535 ? "" : "a number 1–65535"
}

function intRange(s, lo, hi) {
    s = String(s ?? "").trim()
    if (!/^\d+$/.test(s)) return "a whole number " + lo + "–" + hi
    const n = Number(s)
    return n >= lo && n <= hi ? "" : "a whole number " + lo + "–" + hi
}

// ssh destination: [user@]host
function sshTarget(s) {
    s = String(s ?? "").trim()
    const m = /^(?:([a-zA-Z0-9._-]+)@)?(.+)$/.exec(s)
    if (!m) return "like user@host"
    if (m[1] !== undefined && m[1].startsWith("-")) return "user can't start with \"-\""
    return host(m[2])
}

// a name that becomes a file name (saved themes, settings profiles)
function name(n) {
    n = String(n ?? "").trim()
    if (n === "") return "enter a name"
    if (!/^[A-Za-z0-9 _-]{1,40}$/.test(n)) return "letters, digits, space, _ and - (max 40)"
    return ""
}
