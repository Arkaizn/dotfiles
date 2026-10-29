pragma Singleton
import Quickshell
import QtQuick

// How big each app window draws its content (Ctrl +/−/0, Ctrl + wheel, or
// Settings → App zoom), saved per app in Settings.zoom as a percent string:
//   { "mail": "125", "calendar": "110", "settings": "100", "perfmon": "100", "wizard": "100" }
// The window side is components/ZoomArea.qml.
Singleton {
    id: root

    readonly property var steps: [50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200]
    readonly property var options: steps.map(String)
    readonly property var apps: ["mail", "calendar", "settings", "perfmon", "wizard"]

    function percent(app) {
        const p = parseInt(Settings.zoom[app] ?? "100")
        return steps.includes(p) ? p : 100
    }
    function of(app) { return percent(app) / 100 }

    function set(app, p) {
        if (p === 100) Settings.reset("zoom", app)
        else Settings.set("zoom", app, String(p))
    }
    function by(app, dir) {
        const i = steps.indexOf(percent(app))
        set(app, steps[Math.max(0, Math.min(steps.length - 1, i + dir))])
    }
    function reset(app) { set(app, 100) }

    // a popup (drawn above the window, outside its zoom): the zoom of the app
    // it sits in, found from the item it's attached to
    //   Popup { scale: AppZoom.at(parent); transformOrigin: Popup.TopLeft }
    function at(item) {
        for (let i = item; i; i = i.parent)
            if (typeof i.zoomApp === "string") return i.zoom
        return 1
    }
}
