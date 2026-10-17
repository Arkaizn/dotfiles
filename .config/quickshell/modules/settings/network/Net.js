.pragma library

// Helpers for the network page: validation ("" = fine, else what's wrong),
// nmcli list values, netmask ↔ prefix, durations.

function octetsOk(s) {
    const p = s.split(".")
    return p.length === 4 && p.every(o => /^\d{1,3}$/.test(o) && Number(o) <= 255)
}

function ipv4(s) { return octetsOk(s) ? "" : "not an IPv4 address" }

function ipv6(s) {
    if (!/^[0-9a-fA-F:.]+(%\w+)?$/.test(s) || !s.includes(":")) return "not an IPv6 address"
    const dbl = s.split("::").length - 1
    if (dbl > 1) return "\"::\" only once"
    const groups = s.replace(/%\w+$/, "").split(":").filter(g => g !== "")
    if (groups.some(g => !g.includes(".") && g.length > 4)) return "a group has more than 4 digits"
    if (dbl === 0 && groups.length !== 8 && !s.includes(".")) return "needs 8 groups (or \"::\")"
    return ""
}

function ip(s) { return s.includes(":") ? ipv6(s) : ipv4(s) }

// "192.168.1.5/24" (a bare address gets /24 added by withPrefix)
function ipv4Cidr(s) {
    const m = /^([^/]+)\/(\d{1,2})$/.exec(s)
    if (!m) return octetsOk(s) ? "" : "like 192.168.1.10/24"
    if (!octetsOk(m[1])) return "not an IPv4 address"
    return Number(m[2]) <= 32 ? "" : "prefix is 0–32"
}

function ipv6Cidr(s) {
    const m = /^([^/]+)\/(\d{1,3})$/.exec(s)
    if (!m) return ipv6(s)
    const e = ipv6(m[1])
    if (e) return e
    return Number(m[2]) <= 128 ? "" : "prefix is 0–128"
}

function withPrefix(s, def) { return s.includes("/") ? s : s + "/" + def }

function domain(s) {
    return /^(?=.{1,253}$)([a-zA-Z0-9_]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9_])?\.)*[a-zA-Z0-9_]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.?$/.test(s)
        ? "" : "not a domain name"
}

// "10.0.0.0/8 192.168.1.1 100" — destination, optional next hop and metric
function route4(s) {
    const p = s.trim().split(/\s+/)
    if (ipv4Cidr(p[0]) !== "") return "destination like 10.0.0.0/8"
    if (p[1] !== undefined && ipv4(p[1]) !== "") return "next hop isn't an IPv4 address"
    if (p[2] !== undefined && !/^\d+$/.test(p[2])) return "metric is a number"
    return p.length <= 3 ? "" : "destination, next hop, metric"
}

function route6(s) {
    const p = s.trim().split(/\s+/)
    if (ipv6Cidr(p[0]) !== "") return "destination like fd00::/8"
    if (p[1] !== undefined && ipv6(p[1]) !== "") return "next hop isn't an IPv6 address"
    if (p[2] !== undefined && !/^\d+$/.test(p[2])) return "metric is a number"
    return p.length <= 3 ? "" : "destination, next hop, metric"
}

function mac(s) { return /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/.test(s) ? "" : "like 12:34:56:78:9A:BC" }

// nmcli prints lists as "a, b" or "a,b"; routes as "x/y via metric, …"
function splitList(v) {
    return String(v ?? "").split(",").map(x => x.trim()).filter(x => x !== "" && x !== "--")
}
function joinList(a) { return a.join(",") }

function maskToPrefix(mask) {
    if (!octetsOk(mask)) return 24
    return mask.split(".").map(Number).reduce((n, o) => n + (o >>> 0).toString(2).split("1").length - 1, 0)
}

function prefixToMask(p) {
    const bits = p === 0 ? 0 : (0xffffffff << (32 - p)) >>> 0
    return [24, 16, 8, 0].map(s => (bits >>> s) & 255).join(".")
}

// 86400 → "24 h", 5400 → "1 h 30 min"
function duration(sec) {
    sec = Math.max(0, Math.round(sec))
    const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
    if (d > 0) return d + " d" + (h > 0 ? " " + h + " h" : "")
    if (h > 0) return h + " h" + (m > 0 ? " " + m + " min" : "")
    if (m > 0) return m + " min"
    return sec + " s"
}

// "0" / "-1" / "yes" / "no" style ternaries → bool
function isYes(v) { return v === "yes" || v === "true" || v === "1" }
