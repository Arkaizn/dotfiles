.pragma library

// Sizes for display. bytes: decimal units (settings pages: disks, caches,
// packages); ibytes: binary units (performance monitor: memory, traffic).
function bytes(b) {
    const u = ["B", "KB", "MB", "GB", "TB"]
    let i = 0
    while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
    return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
}

function ibytes(b) {
    const u = ["B", "KiB", "MiB", "GiB", "TiB"]
    let i = 0
    while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
    return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
}

// KiB like `free -h` (the dashboard's memory): "3.5Gi", "13Gi", "189Mi"
function freeH(kib) {
    const u = ["Ki", "Mi", "Gi", "Ti"]
    let i = 0
    while (kib >= 1024 && i < u.length - 1) { kib /= 1024; i++ }
    const one = kib.toFixed(1)
    return (Number(one) < 10 ? one : String(Math.round(kib))) + u[i]
}

// a moment (Date or ms) as its local day "2026-10-23" (calendar keys, IPC) and time "14:05"
function pad2(n) { return String(n).padStart(2, "0") }
function day(t) { const d = new Date(t); return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }
function hm(t) { const d = new Date(t); return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) }
// "just now", "5 min ago", "3 h ago", "2 d ago" (t in ms)
function ago(t) {
    const s = Math.max(0, (Date.now() - t) / 1000)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    return Math.floor(s / 86400) + " d ago"
}
