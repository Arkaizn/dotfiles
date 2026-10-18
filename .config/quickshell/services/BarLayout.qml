pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Which modules sit where on the bar (settings app → Shell → Bar layout).
//
// Zones: left, centerLeft, center, centerRight, right. "center" sits in the
// middle of the bar; centerLeft / centerRight hang off its sides (so the clock
// stays centred while the media player next to it grows).
//
// Stored in Settings.bar:
//   layout:   { left: [ids], centerLeft: [...], center: [...], centerRight: [...], right: [...] }
//   monitors: { "<output name>": { …same shape… } }   own layout for that monitor
// Unknown ids, duplicates and broken values are dropped; a missing layout = default.
Singleton {
    id: root

    readonly property var zones: ["left", "centerLeft", "center", "centerRight", "right"]
    readonly property var zoneNames: ({ left: "Left", centerLeft: "Beside centre (left)", center: "Centre",
                                        centerRight: "Beside centre (right)", right: "Right" })

    // every module the bar can show
    readonly property var modules: [
        { id: "arch",       name: "Launcher button",  icon: "󰣇", desc: "Opens the app launcher" },
        { id: "workspaces", name: "Workspaces",       icon: "󰕰", desc: "niri / Hyprland workspaces" },
        { id: "updater",    name: "Updates",          icon: "󰚰", desc: "Pending package updates" },
        { id: "pull",       name: "Dotfiles pull",    icon: "󰇚", desc: "Runs the dotfiles pull script" },
        { id: "push",       name: "Dotfiles push",    icon: "󰕒", desc: "Runs the dotfiles push script" },
        { id: "tray",       name: "System tray",      icon: "󰀻", desc: "Tray icons of running apps" },
        { id: "music",      name: "Media player",     icon: "󰎆", desc: "Hidden when nothing is playing" },
        { id: "clock",      name: "Clock",            icon: "󰥔", desc: "Time and date; opens the calendar" },
        { id: "cpu",        name: "CPU usage",        icon: "", desc: "Percent, every “Stats refresh” ms" },
        { id: "cputemp",    name: "CPU temperature",  icon: "󰔏", desc: "k10temp / coretemp" },
        { id: "mem",        name: "Memory usage",     icon: "", desc: "Percent used" },
        { id: "gpu",        name: "GPU usage",        icon: "󰢮", desc: "NVIDIA (nvidia-smi); hidden otherwise" },
        { id: "gputemp",    name: "GPU temperature",  icon: "󰢮", desc: "NVIDIA (nvidia-smi); hidden otherwise" },
        { id: "headset",    name: "Headset battery",  icon: "󰋋", desc: "Hidden while the headset is off" },
        { id: "bluetooth",  name: "Bluetooth",        icon: "󰂯", desc: "Opens the Bluetooth menu" },
        { id: "volume",     name: "Volume",           icon: "󰕾", desc: "Scroll to change" },
        { id: "network",    name: "Network",          icon: "󰛳", desc: "Opens the network menu" },
        { id: "notifs",     name: "Notifications",    icon: "󰂚", desc: "Notification centre" },
        { id: "battery",    name: "Battery",          icon: "󰁹", desc: "Hidden without a battery" },
        { id: "power",      name: "Power menu",       icon: "󰐥", desc: "Lock, log out, reboot, …" },
        { id: "recording",  name: "Recording",        icon: "󰑊", desc: "Only while recording / a screenshot countdown runs; click stops" },
        { id: "capture",    name: "Screenshot button", icon: "󰄀", desc: "Opens the capture menu" },
        { id: "powerprofile", name: "Power profile",  icon: "󰗑", desc: "Click cycles power saver / balanced / performance" }
    ]
    readonly property var moduleIds: modules.map(m => m.id)
    function module(id) { return modules.find(m => m.id === id) ?? { id: id, name: id, icon: "?", desc: "" } }

    readonly property var defaultLayout: ({
        left: ["arch", "workspaces", "updater", "pull", "push", "tray"],
        centerLeft: ["music"],
        center: ["clock"],
        centerRight: [],
        right: ["recording", "headset", "bluetooth", "volume", "network", "notifs", "battery", "power"]
    })

    // clean a stored layout: known ids only, each once; null if unusable
    function sanitize(l) {
        if (!l || typeof l !== "object" || Array.isArray(l)) return null
        const seen = {}, out = {}
        let any = false
        for (const z of zones) {
            out[z] = []
            // lists that went through a model (Repeater modelData) are list-like, not arrays
            const list = Array.isArray(l[z]) ? l[z]
                       : l[z] && typeof l[z] === "object" && typeof l[z].length === "number" ? Array.from(l[z]) : null
            if (!list) continue
            any = true
            for (const id of list)
                if (typeof id === "string" && moduleIds.includes(id) && !seen[id]) { seen[id] = true; out[z].push(id) }
        }
        return any ? out : null
    }

    readonly property var globalLayout: sanitize(Settings.bar.layout) ?? defaultLayout
    readonly property var monitorLayouts: {
        const m = Settings.bar.monitors
        const out = {}
        if (m && typeof m === "object" && !Array.isArray(m))
            for (const k in m) { const l = sanitize(m[k]); if (l) out[k] = l }
        return out
    }

    function layoutFor(screenName) { return monitorLayouts[screenName] ?? globalLayout }
    function hasOwn(screenName) { return monitorLayouts[screenName] !== undefined }

    // modules not placed anywhere in a layout
    function unused(l) {
        const used = zones.reduce((a, z) => a.concat(l[z]), [])
        return moduleIds.filter(id => !used.includes(id))
    }

    // ── Editing ("" = all monitors) ─────────────────────────────────────────
    function save(screenName, l) {
        const clean = sanitize(l) ?? defaultLayout
        if (screenName === "") Settings.set("bar", "layout", clean)
        else {
            const m = Object.assign({}, monitorLayouts)
            m[screenName] = clean
            Settings.set("bar", "monitors", m)
        }
    }

    // move `id` to zone `zone` at `index` (removes it from where it was; zone "" = hide)
    function move(screenName, id, zone, index) {
        const cur = layoutFor(screenName)
        const l = {}
        for (const z of zones) l[z] = cur[z].filter(x => x !== id)
        if (zone !== "") {
            const i = Math.max(0, Math.min(index, l[zone].length))
            l[zone].splice(i, 0, id)
        }
        save(screenName, l)
    }

    function setOwn(screenName, on) {
        const m = Object.assign({}, monitorLayouts)
        if (on) m[screenName] = JSON.parse(JSON.stringify(globalLayout))
        else delete m[screenName]
        Settings.set("bar", "monitors", m)
    }

    function reset(screenName) {
        if (screenName === "") Settings.set("bar", "layout", defaultLayout)
        else save(screenName, globalLayout)
    }

    // qs ipc call bar layout ""        → the shared layout (or a monitor's) as JSON
    // qs ipc call bar reset            → default layout everywhere (also drops per-monitor ones)
    IpcHandler {
        target: "bar"
        function layout(screen: string): string { return JSON.stringify(root.layoutFor(screen)) }
        function reset(): void { Settings.set("bar", "monitors", {}); Settings.set("bar", "layout", root.defaultLayout) }
    }
}
