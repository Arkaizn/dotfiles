import QtQuick
import qs.components
import qs.services
import qs.services.lib

// What floats up from a pet and fades: a heart (petted), a "z" (asleep), a
// "!" (a notification). It moves in whole art pixels on a slow timer, like
// the pets, and removes itself.
PixelSprite {
    id: root

    property string kind: "heart"          // a part of PixelBits
    property real startX: 0                // its centre, in the pet
    property real startY: 0                // its bottom edge
    property int step: 0
    property int steps: 14                 // how far it rises (art pixels); less on the bar

    rows: PixelBits.def.parts[kind] ?? []
    palette: PixelBits.def.palette
    // on the wallpaper, not on a panel: fixed light / dark like the desktop widgets
    colors: ({ red: Colors.red, ink: Colors.onWallpaper(0.95), accent: Colors.accent, muted: Colors.onWallpaper(0.6) })

    x: Math.round(startX - width / 2) + (kind === "bang" ? 0 : (step % 4 < 2 ? 0 : px))
    y: startY - height - step * px
    opacity: step < steps - 4 ? 1 : (steps - step) / 4
    z: 5

    Timer {
        interval: root.kind === "z" ? 150 : 100
        repeat: true
        running: true
        onTriggered: if (++root.step >= root.steps) root.destroy()
    }
}
