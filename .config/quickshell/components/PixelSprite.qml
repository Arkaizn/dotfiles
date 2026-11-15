import QtQuick
import qs.services
import qs.services.lib

// Pixel art drawn from text (services/lib/PixelArt.js): one frame of a pet,
// a heart, an obstacle of the offline game. Sharp at any size: each art pixel
// is a square of `px` screen pixels.
//
//   PixelSprite { rows: PixelArt.frame(PetCat.def, "walk0"); palette: PetCat.def.palette; px: 2 }
//   PixelSprite { rows: PixelBits.def.parts.heart; palette: PixelBits.def.palette      // "r" → "red"
//                 colors: ({ red: Colors.red }); px: 2; flipped: true }
//
// palette: character → "#rrggbb", or a name that `colors` turns into a colour
// (so a sprite can follow the scheme). A name `colors` doesn't have is ink.
//
// Nothing is painted here: each frame is a tiny image made once and kept
// (PixelArt.png), every sprite showing that frame shares its texture, and
// changing the frame swaps it. Mirroring and scaling are free.
Image {
    id: root

    property var rows: []
    property var palette: ({})
    property var colors: ({})
    property int px: 2
    property bool flipped: false          // mirrored left ↔ right

    readonly property int artWidth: rows.length > 0 ? rows[0].length : 0
    readonly property int artHeight: rows.length
    // (an Image's implicit size is the picture's own: one pixel per art pixel)
    width: artWidth * px
    height: artHeight * px

    // character → the colour it is right now, as text
    readonly property var resolved: {
        const out = {}
        for (const c in palette) {
            const v = palette[c]
            out[c] = typeof v === "string" && v.startsWith("#") ? v : String(colors[v] ?? Colors.ink)
        }
        return out
    }

    source: PixelArt.png(rows, resolved)
    smooth: false
    mipmap: false
    mirror: flipped
    fillMode: Image.Stretch
    asynchronous: false
    cache: true
}
