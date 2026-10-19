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
