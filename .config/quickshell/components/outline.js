.pragma library

// SVG path builders for the bar + attached-popup outlines (used with PathSvg).
// `i` is the inset (half the stroke width) so the stroke isn't clipped at
// the item edges.

// Popup hanging under the bar.
//   x0/x1      left/right edge of the panel body
//   h          current height (animates during open/close)
//   fl/fr      inverted ("flare") corner radius on the left/right top, 0 = flush
//   r          bottom corner radius
// Open path: starts and ends on the bar line (y = 0) so the top edge — where
// the popup merges into the bar — gets no stroke. Append "Z" for the fill.
function panel(x0, x1, h, fl, fr, r, i) {
    const bx0 = x0 + i, bx1 = x1 - i, by = h - i
    let p = fl > 0 ? `M ${bx0 - fl} 0 A ${fl} ${fl} 0 0 1 ${bx0} ${fl} `
                   : `M ${bx0} 0 `
    p += `L ${bx0} ${by - r} `
    if (r > 0) p += `A ${r} ${r} 0 0 0 ${bx0 + r} ${by} `
    p += `L ${bx1 - r} ${by} `
    if (r > 0) p += `A ${r} ${r} 0 0 0 ${bx1} ${by - r} `
    p += `L ${bx1} ${fr} `
    if (fr > 0) p += `A ${fr} ${fr} 0 0 1 ${bx1 + fr} 0 `
    return p
}

// The bar's border, clockwise from the top-left, skipping the bottom-edge
// ranges in `gaps` ([[x0, x1], ...] in the bar's own coordinates) where a
// popup is attached.
function bar(w, h, tl, tr, br, bl, gaps, i) {
    const R = w - i, B = h - i
    let p = `M ${i} ${i + tl} `
    if (tl > 0) p += `A ${tl} ${tl} 0 0 1 ${i + tl} ${i} `
    p += `L ${R - tr} ${i} `
    if (tr > 0) p += `A ${tr} ${tr} 0 0 1 ${R} ${i + tr} `
    p += `L ${R} ${B - br} `
    if (br > 0) p += `A ${br} ${br} 0 0 1 ${R - br} ${B} `

    // bottom edge, right → left, jumping over the gaps
    const xs = R - br, xe = i + bl
    let cur = xs
    gaps.slice().sort((a, b) => b[1] - a[1]).forEach(g => {
        const g0 = Math.max(g[0], xe), g1 = Math.min(g[1], xs)
        if (g1 <= g0 || g0 >= cur) return
        if (g1 < cur) p += `L ${g1} ${B} `
        p += `M ${g0} ${B} `
        cur = g0
    })
    p += `L ${xe} ${B} `

    if (bl > 0) p += `A ${bl} ${bl} 0 0 1 ${i} ${B - bl} `
    p += `L ${i} ${i + tl} `
    return p
}
