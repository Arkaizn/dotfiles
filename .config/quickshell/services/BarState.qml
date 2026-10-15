pragma Singleton
import Quickshell

// Which popups are currently attached under the bar.
// Each entry: { id, screen, x0, x1, side } — x0/x1 in screen coordinates,
// side is "left" | "right" | "center" (which bar edge the popup is flush with).
// The bar uses this to square its corner and leave a gap in its border
// where the popup joins it, so bar + popup read as one outline.
Singleton {
    property var attachments: []

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
