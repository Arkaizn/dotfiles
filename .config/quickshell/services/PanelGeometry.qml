pragma Singleton
import Quickshell
import QtQuick
import qs.services.lib

// Where the bar sits and how big / where the panels are (Part 6, panel
// editor; Settings → Panels, or live: EditMode "panels"). One place for all of
// it: the bar, BarPopup (dashboard, control center), the launcher read it here.
// Values, defaults and limits: services/lib/PanelGeom.js. Stored in
// Settings.panels, only what differs from the default.
Singleton {
    id: root

    readonly property var g: PanelGeom.resolve(Settings.panels)

    // ── the bar ─────────────────────────────────────────────────────────────
    readonly property string barEdge: g.bar.edge
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property int barThickness: g.bar.thickness
    // gap between the screen edge and the bar (Properties.barInset is the side gap)
    readonly property int barGap: 10
    // the bar's buttons keep their distance to its edges, so they grow with it
    // (Properties.buttonHeight at the default 50 px)
    readonly property int barButtonHeight: Math.max(20, Properties.buttonHeight + barThickness - defaults.bar.thickness)

    // ── panels ──────────────────────────────────────────────────────────────
    function panel(id) { return g[id] }
    readonly property var dashboard: g.dashboard
    readonly property var controlCenter: g.controlCenter
    readonly property var notifications: g.notifications
    readonly property var launcher: g.launcher
    function launcherView(view) { return g.launcher.views[view] ?? g.launcher.views.apps }
    readonly property var limits: PanelGeom.limits
    readonly property var defaults: PanelGeom.defaults

    // set one value of a panel (clamped; back to the default = the key goes)
    function set(id, key, value) {
        const p = PanelGeom.store(Settings.panels[id], id, key, value)
        p === null ? Settings.reset("panels", id) : Settings.set("panels", id, p)
    }
    function setView(view, w, h) {
        const views = JSON.parse(JSON.stringify(g.launcher.views))
        views[view] = { w: w, h: h }
        set("launcher", "views", views)
    }
    // control center button cards: { perRow, tile } (tiles per row, tile height)
    function card(id) { return g.cards[id] ?? PanelGeom.card(undefined) }
    function setCard(id, key, value) {
        const c = PanelGeom.storeCard(Settings.panels.cards, id, key, value)
        c === null ? Settings.reset("panels", "cards") : Settings.set("panels", "cards", c)
    }
    function reset(id) { id ? Settings.reset("panels", id) : Settings.resetGroup("panels") }
    readonly property bool changed: Object.keys(Settings.panels ?? {}).length > 0
}
