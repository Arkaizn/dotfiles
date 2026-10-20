pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// Desktop widgets: clocks, calendar, media player, stats, … on the wallpaper,
// below every window (modules/desktop). Each instance has its own place,
// rotation, size, monitors and options; a type can be placed any number of
// times. Geometry / snapping / the settings check: services/lib/DeskWidgets.js.
//
//   Settings.desktopWidgets: { enabled, monitors: [ids] (all widgets; [] = every monitor),
//                              instances: [{ id, type, x, y, rot, scale, monitors, opts }] }
//
// Live editor (modules/desktop/DesktopEditor.qml): long-press a widget, the
// "Edit on desktop" button in Settings → Desktop widgets, or
//   qs ipc call desktopWidgets edit | stop | toggle | add <type> | list
Singleton {
    id: root

    // ── Types ───────────────────────────────────────────────────────────────
    // option kinds: bool, number (min, max, step), text (multiline), choice (choices), list (apps)
    readonly property var commonOpts: [
        { key: "background", label: "Background", kind: "choice", def: "card",
          choices: [{ label: "Card", value: "card" }, { label: "Glass", value: "glass" }, { label: "None", value: "none" }] },
        { key: "opacity", label: "Opacity", kind: "number", min: 0.2, max: 1, step: 0.05, def: 1 }
    ]
    readonly property var types: [
        { type: "clock", name: "Clock", icon: "󰥔", desc: "Big digital or analog clock with the date", opts: [
            { key: "style", label: "Style", kind: "choice", def: "digital",
              choices: [{ label: "Digital", value: "digital" }, { label: "Analog", value: "analog" }, { label: "Words", value: "words" }] },
            { key: "size", label: "Size", kind: "number", min: 32, max: 240, step: 4, def: 96 },
            { key: "seconds", label: "Seconds", kind: "bool", def: false },
            { key: "date", label: "Date", kind: "bool", def: true },
            { key: "h12", label: "12-hour", kind: "bool", def: false }] },
        { type: "calendar", name: "Calendar", icon: "󰃭", desc: "Month view; dots on days with events", opts: [
            { key: "sunday", label: "Weeks start on Sunday", kind: "bool", def: false },
            { key: "events", label: "Event dots", kind: "bool", def: true }] },
        { type: "media", name: "Media player", icon: "󰎆", desc: "Cover, title, play / pause / skip, progress", opts: [
            { key: "cover", label: "Cover", kind: "bool", def: true },
            { key: "hideIdle", label: "Hide without a player", kind: "bool", def: false }] },
        { type: "system", name: "System", icon: "󰍛", desc: "CPU, memory, temperature, GPU with history graphs", opts: [
            { key: "cpu", label: "CPU", kind: "bool", def: true },
            { key: "mem", label: "Memory", kind: "bool", def: true },
            { key: "temp", label: "Temperature", kind: "bool", def: true },
            { key: "gpu", label: "GPU (NVIDIA)", kind: "bool", def: true },
            { key: "graph", label: "History graphs", kind: "bool", def: true },
            { key: "uptime", label: "Uptime", kind: "bool", def: false }] },
        { type: "network", name: "Network speed", icon: "󰛳", desc: "Download / upload now, with a graph", opts: [
            { key: "graph", label: "Graph", kind: "bool", def: true }] },
        { type: "disk", name: "Disks", icon: "󰋊", desc: "Used / free space of your drives", opts: [
            { key: "paths", label: "Folders", kind: "list", item: "path", def: ["/", "/home"] }] },
        { type: "battery", name: "Battery", icon: "󰁹", desc: "Charge, charging, time left", opts: [] },
        { type: "events", name: "Upcoming events", icon: "󰸗", desc: "Next events from your calendars", opts: [
            { key: "count", label: "Events", kind: "number", min: 1, max: 12, step: 1, def: 5 },
            { key: "days", label: "Days ahead", kind: "number", min: 1, max: 60, step: 1, def: 14 }] },
        { type: "countdown", name: "Countdown", icon: "󰔟", desc: "Days / hours until a date", opts: [
            { key: "title", label: "Title", kind: "text", def: "Holidays" },
            { key: "when", label: "Date (YYYY-MM-DD HH:MM)", kind: "text", def: "" }] },
        { type: "note", name: "Note", icon: "󰎚", desc: "Sticky note with your text", opts: [
            { key: "text", label: "Text", kind: "text", multiline: true, def: "Note" },
            { key: "size", label: "Text size", kind: "number", min: 10, max: 64, step: 1, def: 16 },
            { key: "align", label: "Align", kind: "choice", def: "left",
              choices: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }] }] },
        { type: "apps", name: "App shortcuts", icon: "󰀻", desc: "Icons that start apps", opts: [
            { key: "apps", label: "Apps", kind: "list", item: "app", def: [] },
            { key: "iconSize", label: "Icon size", kind: "number", min: 24, max: 128, step: 4, def: 44 },
            { key: "labels", label: "Names", kind: "bool", def: true },
            { key: "columns", label: "Columns", kind: "number", min: 1, max: 12, step: 1, def: 4 }] },
        { type: "image", name: "Picture", icon: "󰋩", desc: "A picture frame", opts: [
            { key: "path", label: "Picture file", kind: "text", file: true, def: "" },
            { key: "width", label: "Width", kind: "number", min: 60, max: 1200, step: 10, def: 280 },
            { key: "radius", label: "Rounded corners", kind: "number", min: 0, max: 200, step: 2, def: 14 }] }
    ]
    readonly property var typeIds: types.map(t => t.type)
    function typeInfo(t) { return types.find(x => x.type === t) ?? { type: t, name: t, icon: "?", desc: "", opts: [] } }
    function specs(t) { return typeInfo(t).opts.concat(commonOpts) }
    // for DeskWidgets.validate: { type: [specs] }
    readonly property var specMap: {
        const m = {}
        for (const t of types) m[t.type] = t.opts.concat(commonOpts)
        return m
    }
    // an instance's options with the defaults filled in
    function optsOf(inst) {
        const o = {}
        for (const s of specs(inst?.type ?? "")) o[s.key] = inst?.opts?.[s.key] ?? s.def
        return o
    }

    // ── State ───────────────────────────────────────────────────────────────
    readonly property var conf: Settings.desktopWidgets
    readonly property bool enabled: conf.enabled ?? true
    readonly property var monitors: conf.monitors ?? []
    readonly property var instances: (conf.instances ?? []).filter(w => typeIds.includes(w.type))
    readonly property var byId: {
        const m = {}
        for (const w of instances) m[w.id] = w
        return m
    }

    function monitorsOf(inst) { return inst.monitors ?? monitors }
    // the instance ids shown on a screen
    function idsFor(screenName) {
        const outs = Monitors.outputs
        return instances.filter(w => DeskWidgets.showsOn(monitorsOf(w), screenName, outs)).map(w => w.id)
    }

    // what a monitor choice stores for a connected monitor: "make model serial",
    // or the output name when that isn't unique / unknown (like the lockscreen)
    function keyFor(o) {
        const unique = Monitors.outputs.filter(x => x.ident === o.ident).length === 1
        return unique && !o.ident.startsWith("Unknown Unknown") ? o.ident : o.name
    }
    function keyForScreen(name) {
        const o = Monitors.outputs.find(x => x.name === name)
        return o ? keyFor(o) : name
    }
    // monitors to choose from: connected ones, then chosen ones that aren't connected
    //   [{ key, label, connected }]
    function choices(chosen) {
        const names = Quickshell.screens.map(s => s.name)
        const out = Monitors.outputs.filter(o => names.includes(o.name))
            .map(o => ({ key: keyFor(o), label: o.name + "  " + o.ident.replace(/ Unknown$/, "").replace(/^Unknown Unknown.*/, ""), connected: true }))
        for (const k of chosen ?? []) if (!out.some(c => c.key === k)) out.push({ key: k, label: k.replace(/ Unknown$/, ""), connected: false })
        // screens Monitors doesn't know (yet)
        for (const n of names) if (!out.some(c => c.key === n || c.label.startsWith(n + " "))) out.push({ key: n, label: n, connected: true })
        return out
    }

    // ── Changes (saved to settings.json) ────────────────────────────────────
    function _save(list) { Settings.set("desktopWidgets", "instances", list) }
    function setEnabled(on) { Settings.set("desktopWidgets", "enabled", on) }
    function setMonitors(ids) { Settings.set("desktopWidgets", "monitors", ids) }

    function add(type, x, y, screenName) {
        const id = DeskWidgets.newId(type, instances.map(w => w.id))
        // added on a monitor where "all widgets" don't show: on that monitor
        const mons = screenName && !DeskWidgets.showsOn(monitors, screenName, Monitors.outputs) ? [keyForScreen(screenName)] : null
        const w = { id: id, type: type, x: x ?? 0.5, y: y ?? 0.4, rot: 0, scale: 1, monitors: mons, opts: {} }
        _save((conf.instances ?? []).concat([w]))
        selected = id
        return id
    }
    function update(id, patch) {
        _save((conf.instances ?? []).map(w => w.id === id ? Object.assign({}, w, patch) : w))
    }
    function setOpt(id, key, value) {
        const w = byId[id]
        if (!w) return
        const o = Object.assign({}, w.opts ?? {})
        o[key] = value
        update(id, { opts: o })
    }
    function remove(id) {
        _save((conf.instances ?? []).filter(w => w.id !== id))
        if (selected === id) selected = ""
    }
    function duplicate(id) {
        const w = byId[id]
        if (!w) return ""
        const n = Object.assign({}, JSON.parse(JSON.stringify(w)), {
            id: DeskWidgets.newId(w.type, instances.map(x => x.id)),
            x: Math.min(1, w.x + 0.03), y: Math.min(1, w.y + 0.03) })
        _save((conf.instances ?? []).concat([n]))
        selected = n.id
        return n.id
    }
    // to the front (drawn last = on top of the others)
    function raise(id) {
        const l = conf.instances ?? []
        const w = l.find(x => x.id === id)
        if (w && l[l.length - 1] !== w) _save(l.filter(x => x !== w).concat([w]))
    }

    // ── Live editor ─────────────────────────────────────────────────────────
    property bool editing: false
    property string editScreen: ""          // gets the keyboard (Esc, Delete, arrows)
    property string selected: ""
    property bool fileDialog: false         // the editor steps aside for a file dialog
    function startEdit(screenName, id) {
        selected = id ?? ""
        if (!screenName && (Compositor.isNiri || Compositor.isHyprland)) {
            Compositor.focusedOutput(name => { root.editScreen = name || (Quickshell.screens[0]?.name ?? ""); root.editing = true })
            return
        }
        editScreen = screenName || (Quickshell.screens[0]?.name ?? "")
        editing = true
    }
    function stopEdit() { editing = false; selected = ""; fileDialog = false }

    // monitor names ↔ "make model serial" for the per-monitor choice
    Component.onCompleted: Monitors.refresh()
    Connections { target: Quickshell; function onScreensChanged() { Monitors.refresh() } }

    IpcHandler {
        target: "desktopWidgets"
        function edit(): void { root.startEdit("") }
        function stop(): void { root.stopEdit() }
        function toggle(): void { root.editing ? root.stopEdit() : root.startEdit("") }
        function add(type: string): string { return root.typeIds.includes(type) ? root.add(type) : "unknown type; one of " + root.typeIds.join(" ") }
        function list(): string { return root.instances.map(w => w.id + " " + w.type + " " + w.x + "," + w.y).join("\n") }
    }
}
