.pragma library

// A pywal theme (colors.json shape) rebuilt from scratch before `wal` sees
// it. pywal copies the values unchecked into ~/.cache/wal/colors.sh
// (`color0='…'`, `wallpaper='…'`), which shell scripts `source` — a theme
// file with a crafted value would run as code. So only plain #rrggbb colours
// go through, the wallpaper only as an absolute path without quotes or shell
// characters (dropped otherwise), and nothing else.
//   clean(obj) → { ok: true, theme } | { ok: false, error }
//   wallpaperPath(p) → whether p may become the wallpaper (from outside: the file
//                      manager's "Set as wallpaper"): the same rule, and a picture's extension

const HEX = /^#[0-9a-fA-F]{6}$/
const SAFE_PATH = /^\/[^'"`$\\\n\r\0]*$/

function clean(j) {
    if (j === null || typeof j !== "object" || Array.isArray(j)) return { ok: false, error: "not a pywal theme (expected an object)" }
    const c = j.colors, sp = j.special
    if (c === null || typeof c !== "object") return { ok: false, error: "not a pywal theme (no \"colors\")" }
    const colors = {}
    for (let i = 0; i < 16; i++) {
        const v = c["color" + i]
        if (typeof v !== "string" || !HEX.test(v)) return { ok: false, error: "colors.color" + i + " must be #rrggbb" }
        colors["color" + i] = v
    }
    const special = {}
    for (const k of ["background", "foreground", "cursor"]) {
        const v = sp?.[k] ?? (k === "cursor" ? sp?.foreground : undefined)
        if (typeof v !== "string" || !HEX.test(v)) return { ok: false, error: "special." + k + " must be #rrggbb" }
        special[k] = v
    }
    const theme = { special: special, colors: colors }
    if (typeof j.wallpaper === "string" && SAFE_PATH.test(j.wallpaper) && j.wallpaper.length < 4096) theme.wallpaper = j.wallpaper
    const a = Number(j.alpha)
    if (j.alpha !== undefined && Number.isFinite(a) && a >= 0 && a <= 100) theme.alpha = String(Math.round(a))
    return { ok: true, theme: theme }
}

const IMAGE = /\.(jpe?g|png|webp|gif|bmp|tiff?|avif|jxl)$/i
function wallpaperPath(p) {
    return typeof p === "string" && p.length < 4096 && SAFE_PATH.test(p) && IMAGE.test(p) && p.indexOf("/../") < 0
}
