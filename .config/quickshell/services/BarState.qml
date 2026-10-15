pragma Singleton
import Quickshell

// Which popups are currently attached under the bar.
// Each entry: { id, screen, x0, x1, side } — x0/x1 in screen coordinates,
// side is "left" | "right" | "center" (which bar edge the popup is flush with).
// The bar uses this to square its corner and leave a gap in its border
// where the popup joins it, so bar + popup read as one outline.
Singleton {
    property var attachments: []

    // screen name -> true while the pointer is over that screen's bar
    // (BarPopup won't auto-close while the pointer is on the bar)
    property var hoveredBars: ({})

    function setBarHovered(screen, hovered) {
        const next = Object.assign({}, hoveredBars)
        next[screen] = hovered
        hoveredBars = next
    }

    function attach(id, screen, x0, x1, side) {
        attachments = attachments.filter(a => a.id !== id).concat([{ id, screen, x0, x1, side }])
    }

    function detach(id) {
        attachments = attachments.filter(a => a.id !== id)
    }

    function forScreen(screenName) {
        return attachments.filter(a => a.screen === screenName)
    }
}
