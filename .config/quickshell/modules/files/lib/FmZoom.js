.pragma library

// The folder view's icon sizes (Ctrl + wheel, Ctrl +/−/0 over the view; D0-9).
// Steps, not free values: each one is a size the rows / tiles are laid out for.
//   steps[mode] · def[mode] · step(mode, size, dir)  dir 0 = back to the default

var steps = { list: [16, 20, 24, 32, 40, 48, 64, 80], grid: [48, 64, 80, 96, 128, 160, 192, 256] }
var def = { list: 20, grid: 64 }

function clamp(mode, size) {
    const s = steps[mode] || steps.list
    let best = s[0]
    for (const v of s) if (Math.abs(v - size) < Math.abs(best - size)) best = v
    return best
}

function step(mode, size, dir) {
    if (dir === 0) return def[mode] || def.list
    const s = steps[mode] || steps.list
    const i = s.indexOf(clamp(mode, size))
    return s[Math.max(0, Math.min(s.length - 1, i + (dir > 0 ? 1 : -1)))]
}
