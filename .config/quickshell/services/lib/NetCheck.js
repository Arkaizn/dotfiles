.pragma library

// Parsers for the connectivity check of Settings → Diagnostics (no QML, unit-tested).
// The check prints sections "@@NAME <arg>" followed by their lines:
//   @@URI   <NetworkManager's connectivity check address, busctl format: s "http://…">
//   @@GW    <gateway>   + ping -q summary
//   @@NET   <address>   + ping -q summary
//   @@DNS   "ok <ms>" | "fail"
function sections(text) {
    const out = {}
    let cur = null
    for (const line of String(text).split("\n")) {
        const m = /^@@([A-Z]+)\s*(.*)$/.exec(line)
        if (m) { cur = out[m[1]] = { arg: m[2].trim(), lines: [] }; continue }
        if (cur && line.trim() !== "") cur.lines.push(line)
    }
    return out
}

// ping -q summary → { sent, received, loss (%), avg (ms) | null }; null without a summary
function ping(lines) {
    const t = (lines ?? []).join("\n")
    const s = /(\d+) packets transmitted, (\d+) (?:packets )?received/.exec(t)
    if (!s) return null
    const loss = /([\d.]+)% packet loss/.exec(t)
    const rtt = /= [\d.]+\/([\d.]+)\/[\d.]+/.exec(t)
    return { sent: Number(s[1]), received: Number(s[2]), loss: loss ? Number(loss[1]) : 100, avg: rtt ? Number(rtt[1]) : null }
}

// the whole check → { uri, gateway, gwPing, internet, netPing, dns: ms | -1 (failed) | null }
function parse(text) {
    const s = sections(text)
    const uri = /"(.*)"/.exec(s.URI?.arg ?? "")
    const dns = /^ok (\d+)/.exec(s.DNS?.lines[0] ?? "")
    return {
        uri: uri ? uri[1] : "",
        gateway: s.GW?.arg ?? "", gwPing: ping(s.GW?.lines),
        internet: s.NET?.arg ?? "", netPing: ping(s.NET?.lines),
        dns: dns ? Number(dns[1]) : s.DNS ? -1 : null
    }
}

// one ping result as text: "2.3 ms", "2.3 ms, 33% lost", "no answer"
function pingText(p) {
    if (!p) return "not checked"
    if (p.received === 0 || p.avg === null) return "no answer"
    return (p.avg < 10 ? p.avg.toFixed(1) : Math.round(p.avg)) + " ms" + (p.loss > 0 ? ", " + Math.round(p.loss) + "% lost" : "")
}
