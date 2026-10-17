import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "network"
import "wm"
import "SettingsSearch.js" as SI

// Settings app: a normal (floating) window to change the Properties.qml
// values and some compositor settings. Changes apply live and are saved to
// settings.json (services/Settings.qml); niri ones go to niri's override
// file (services/NiriSettings.qml), Hyprland ones to Hyprland's
// (services/HyprSettings.qml). Only the running compositor's pages show.
//
// Open it with:  qs ipc call settings toggle   (Mod+S, set in the override file)
//                qs ipc call settings openPage <id>   (ids below, e.g. niriLayout)
Scope {
    id: root

    // kept across shell reloads (config edits etc.): an open window comes back
    property alias open: persist.open
    property alias pageId: persist.pageId
    PersistentProperties {
        id: persist
        reloadableId: "settingsWindow"
        property bool open: false
        property string pageId: "appearance"
    }

    // open, or bring the already open window to the front (the compositor
    // focuses it, switching workspace / monitor if needed)
    function show() {
        if (root.open) Compositor.focusWindow(NiriSettings.windowTitle)
        root.open = true
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.open = !root.open }
        function open(): void { root.show() }
        function close(): void { root.open = false }
        // e.g. qs ipc call settings openPage niriInput
        function openPage(id: string): void {
            if (root.visiblePages.some(p => p.id === id)) root.pageId = id
            root.show()
        }
        // the cheatsheet's edit button: Keybinds page with that bind's editor
        // (keys normalized like Keybinds.normKeys, e.g. "mod+shift+s")
        function editKeybind(keys: string): void {
            root.pendingKeybind = keys
            root.pageId = "keybinds"
            root.show()
        }
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // "properties" items are complete here; "niri" / "hyprland" items only name
    // a key of NiriSettings.schema / HyprSettings.schema and add layout hints
    // (sub / dependsOn). Pages with `wm` only show on that compositor.
    property string pendingKeybind: ""
    property string pendingAnchor: ""      // where on a custom page to open (search: "hosts", "profile:<uuid>", …)
    property string flashKey: ""           // "store.key" of a setting to scroll to and flash
    readonly property string wm: Compositor.isHyprland ? "hyprland" : "niri"
    readonly property string wmGroup: Compositor.isHyprland ? "Hyprland" : "Niri"
    readonly property var visiblePages: pages.filter(p => !p.wm || p.wm === wm)

    readonly property var pages: [
        { id: "profile", group: "Shell", icon: "󰀄", title: "Profile", custom: "profile",
          desc: "Your picture and name on the dashboard and lockscreen" },

        { id: "appearance", group: "Shell", icon: "󰏘", title: "Appearance", store: "properties",
          desc: "Font, text and icons used all over the shell",
          sections: [
            { title: "Text", items: [
                { key: "fontFamily", type: "font", label: "Font", desc: "Used by the bar, popups and widgets" },
                { key: "pixelSize", type: "int", min: 8, max: 24, label: "Text size", desc: "Bar labels and stats" },
                { key: "fontBold", type: "bool", label: "Bold button text" },
                { key: "color", keywords: "text color font colour icon tint", type: "color", label: "Text & icon color", desc: "Buttons, fields and bar icons" } ] },
            { title: "Icons", items: [
                { key: "iconSize", type: "int", min: 10, max: 32, label: "Icon size", desc: "Bar buttons, tray and profile" } ] } ] },

        { id: "bar", group: "Shell", icon: "󰍜", title: "Bar", store: "properties",
          desc: "Shape and spacing of the top bar",
          sections: [
            { title: "Shape", items: [
                { key: "barRadius", keywords: "round rounded", type: "int", min: 0, max: 30, label: "Corner radius" },
                { key: "barInset", keywords: "margin gap offset", type: "int", min: 0, max: 40, label: "Distance to screen edge", desc: "Also where popups attach" } ] },
            { title: "Content", items: [
                { key: "barMarginLeft", type: "int", min: 0, max: 60, label: "Left padding" },
                { key: "barMarginRight", type: "int", min: 0, max: 60, label: "Right padding" },
                { key: "spacing", type: "int", min: 0, max: 24, label: "Space between modules" },
                { key: "interval", type: "int", min: 100, max: 5000, step: 100, label: "Stats refresh (ms)",
                  desc: "How often CPU, GPU and memory update" } ] } ] },

        { id: "panels", group: "Shell", icon: "󰖯", title: "Panels", store: "properties",
          desc: "Bar background, popups, dashboard, launcher and cards",
          sections: [
            { title: "Colors", items: [
                { key: "panelColor", keywords: "transparency opacity transparent background color alpha", type: "color", label: "Panel background", desc: "Bar and every popup" },
                { key: "panelBorder", keywords: "outline color transparency", type: "color", label: "Panel border" },
                { key: "cardBorder", keywords: "outline color transparency", type: "color", label: "Card border", desc: "Inner cards in the dashboard and control center" },
                { key: "panelBorderWidth", keywords: "outline thickness", type: "real", min: 0, max: 4, step: 0.5, label: "Border width" } ] },
            { title: "Corners", items: [
                { key: "panelRadius", type: "int", min: 0, max: 48, label: "Big panels",
                  desc: "Dashboard, notification center, launcher, lockscreen" },
                { key: "popupRadius", type: "int", min: 0, max: 32, label: "Notification popups" },
                { key: "flareRadius", type: "int", min: 0, max: 48, label: "Bar flares",
                  desc: "Inverted corners where a popup meets the bar" } ] } ] },

        { id: "buttons", group: "Shell", icon: "󰆽", title: "Buttons", store: "properties",
          desc: "Size and shape of buttons",
          sections: [
            { title: "Size", items: [
                { key: "buttonHeight", type: "int", min: 20, max: 48, label: "Height", desc: "Bar buttons, icon buttons, fields" },
                { key: "buttonWidth", type: "int", min: 12, max: 48, label: "Bar button padding", desc: "Extra width around bar button content" } ] },
            { title: "Corners", items: [
                { key: "radius", type: "int", min: 0, max: 20, label: "Buttons & fields" },
                { key: "buttonradius", type: "int", min: 0, max: 20, label: "Bar stats" } ] } ] },

        { id: "motion", group: "Shell", icon: "󰑮", title: "Motion", store: "properties",
          desc: "Hover and press feedback",
          sections: [
            { title: "Buttons", items: [
                { key: "bDuration", keywords: "speed animation time duration", type: "int", min: 0, max: 600, step: 10, label: "Animation length (ms)" },
                { key: "onEnteredButtonScale", keywords: "hover grow bigger animation", type: "real", min: 1, max: 1.3, step: 0.01, label: "Hover zoom" },
                { key: "onPressedButtonScale", keywords: "click shrink smaller animation", type: "real", min: 0.7, max: 1, step: 0.01, label: "Press shrink" },
                { key: "onEnteredTextScale", type: "real", min: 1, max: 1.5, step: 0.01, label: "Workspace & tray hover zoom" } ] } ] },

        { id: "battery", group: "System", icon: "󰁹", title: "Battery", store: "battery",
          desc: "Warnings when the battery runs low",
          sections: [
            { title: "Low battery", items: [
                { key: "lowAlert", type: "bool", def: true, label: "Low battery warning",
                  desc: "A notification to plug in, repeated while the battery is low" },
                { key: "lowLevel", type: "int", def: 20, min: 5, max: 50, dependsOn: "lowAlert",
                  label: "Below (%)" },
                { key: "lowInterval", type: "int", def: 5, min: 1, max: 30, dependsOn: "lowAlert",
                  label: "Repeat every (minutes)" },
                { key: "testLow", type: "button", icon: "󰂃", text: "Send test", dependsOn: "lowAlert",
                  label: "Try it", run: () => BatteryAlerts.test(false) } ] },
            { title: "Critical battery", items: [
                { key: "criticalAlert", type: "bool", def: true, label: "Critical battery warning",
                  desc: "Urgent notification, more often" },
                { key: "criticalLevel", type: "int", def: 10, min: 2, max: 30, dependsOn: "criticalAlert",
                  label: "Below (%)" },
                { key: "criticalInterval", type: "int", def: 1, min: 1, max: 10, dependsOn: "criticalAlert",
                  label: "Repeat every (minutes)" },
                { key: "testCritical", type: "button", icon: "󰂃", text: "Send test", dependsOn: "criticalAlert",
                  label: "Try it", run: () => BatteryAlerts.test(true) } ] } ] },

        { id: "network", group: "System", icon: "󰛳", title: "Network", custom: "network",
          desc: "Interfaces, IP settings, DNS and profiles (NetworkManager)" },

        { id: "keybinds", group: wmGroup, icon: "󰌌", title: "Keybinds", custom: "keybinds",
          desc: "Search, change, disable and add keybinds" },
        { id: "autostart", group: wmGroup, icon: "󰐊", title: "Autostart", custom: "autostart",
          desc: "Programs started at login" },
        { id: "syntax", group: wmGroup, icon: "󰅩", title: "Syntax", custom: "syntax",
          desc: "How the shell writes the compositor config" },
        { id: "import", group: wmGroup, icon: "󰋺", title: "Import custom", custom: "import",
          desc: "Move autostart and keybinds from ~/.config/custom into the settings" },

        { id: "monitors", group: wmGroup, icon: "󰍹", title: "Monitors", custom: "monitors",
          desc: "Arrange screens, resolution, refresh rate and scale" },

        { id: "calendar", group: "Apps", icon: "󰃭", title: "Calendar", store: "calendar",
          desc: "Reminders and syncing of the calendar app",
          sections: [
            { title: "Reminders", items: [
                { key: "reminders", type: "bool", def: true, label: "Reminders",
                  desc: "Notification before an event starts" },
                { key: "defaultReminder", type: "choice", def: "10", options: ["off", "5", "10", "15", "30", "60"],
                  dependsOn: "reminders", label: "Default reminder (minutes before)",
                  desc: "For events that don't have their own reminder" },
                { key: "allDayReminder", type: "bool", def: false, dependsOn: "reminders",
                  label: "All-day events", desc: "Remind at 09:00 on the day" } ] },
            { title: "View", items: [
                { key: "defaultView", type: "choice", def: "month", options: ["day", "week", "month", "agenda"],
                  label: "Open in", desc: "View when the calendar starts" },
                { key: "dayStart", type: "choice", def: "7", options: ["6", "7", "8", "9", "10"],
                  label: "Day starts at", desc: "Where the day and week views scroll to" },
                { key: "weekNumbers", type: "bool", def: true, label: "Week numbers" } ] },
            { title: "Sync", items: [
                { key: "syncMinutes", type: "choice", def: "15", options: ["5", "15", "30", "60"],
                  label: "Sync every (minutes)", desc: "In the background too, for the dashboard and reminders" } ] } ] },

        { id: "niriLayout", wm: "niri", group: "Niri", icon: "󰕰", title: "Layout", store: "niri",
          desc: "How windows are placed",
          sections: [
            { title: "Windows", items: [
                { key: "gaps" }, { key: "centerColumn" }, { key: "columnWidth" }, { key: "cornerRadius" } ] },
            { title: "Apps", items: [ { key: "preferNoCsd" } ] } ] },

        { id: "niriLooks", wm: "niri", group: "Niri", icon: "󰖲", title: "Decorations", store: "niri",
          desc: "Focus ring, border and shadows",
          sections: [
            { title: "Focus ring", items: [
                { key: "ringOn" },
                { key: "ringWidth", dependsOn: "ringOn" },
                { key: "ringActive", dependsOn: "ringOn" },
                { key: "ringInactive", dependsOn: "ringOn" } ] },
            { title: "Border", items: [
                { key: "borderOn" },
                { key: "borderWidth", dependsOn: "borderOn" },
                { key: "borderInactive", dependsOn: "borderOn" },
                { key: "borderUrgent", dependsOn: "borderOn" } ] },
            { title: "Shadow", items: [
                { key: "shadowOn" },
                { key: "shadowSoftness", dependsOn: "shadowOn" },
                { key: "shadowSpread", dependsOn: "shadowOn" },
                { key: "shadowColor", dependsOn: "shadowOn" } ] } ] },

        { id: "niriEffects", wm: "niri", group: "Niri", icon: "󰂵", title: "Effects", store: "niri",
          desc: "Animations and blur",
          sections: [
            { title: "Animations", items: [ { key: "animationsOn" }, { key: "slowdown", dependsOn: "animationsOn" } ] },
            { title: "Blur", items: [ { key: "appBlur" }, { key: "blurPasses" }, { key: "blurOffset" } ] } ] },

        { id: "niriInput", wm: "niri", group: "Niri", icon: "󰌌", title: "Input", store: "niri",
          desc: "Keyboard, touchpad, mouse and cursor",
          sections: [
            { title: "Keyboard", items: [ { key: "kbLayout" }, { key: "numlock" } ] },
            { title: "Pointer", items: [ { key: "touchpadAccel" }, { key: "mouseAccel" }, { key: "cursorSize" } ] } ] },

        { id: "hyprLayout", wm: "hyprland", group: "Hyprland", icon: "󰕰", title: "Layout", store: "hyprland",
          desc: "How windows are placed",
          sections: [
            { title: "Tiling", items: [ { key: "layout" }, { key: "gapsIn" }, { key: "gapsOut" } ] },
            { title: "Corners", items: [ { key: "rounding" }, { key: "roundingPower" } ] } ] },

        { id: "hyprLooks", wm: "hyprland", group: "Hyprland", icon: "󰖲", title: "Decorations", store: "hyprland",
          desc: "Borders, opacity and shadows",
          sections: [
            { title: "Border", items: [ { key: "borderSize" }, { key: "activeBorder" }, { key: "inactiveBorder" } ] },
            { title: "Opacity", items: [
                { key: "activeOpacity" }, { key: "inactiveOpacity" },
                { key: "dimInactive" }, { key: "dimStrength", dependsOn: "dimInactive" } ] },
            { title: "Shadow", items: [
                { key: "shadowOn" },
                { key: "shadowRange", dependsOn: "shadowOn" },
                { key: "shadowPower", dependsOn: "shadowOn" },
                { key: "shadowColor", dependsOn: "shadowOn" } ] } ] },

        { id: "hyprEffects", wm: "hyprland", group: "Hyprland", icon: "󰂵", title: "Effects", store: "hyprland",
          desc: "Animations and blur",
          sections: [
            { title: "Animations", items: [ { key: "animationsOn" } ] },
            { title: "Blur", items: [
                { key: "blurOn" },
                { key: "blurSize", dependsOn: "blurOn" },
                { key: "blurPasses", dependsOn: "blurOn" },
                { key: "blurVibrancy", dependsOn: "blurOn" },
                { key: "blurXray", dependsOn: "blurOn" } ] } ] },

        { id: "hyprInput", wm: "hyprland", group: "Hyprland", icon: "󰌌", title: "Input", store: "hyprland",
          desc: "Keyboard, mouse and touchpad",
          sections: [
            { title: "Keyboard", items: [ { key: "kbLayout" }, { key: "numlock" } ] },
            { title: "Pointer", items: [ { key: "sensitivity" }, { key: "accelProfile" }, { key: "followMouse" } ] },
            { title: "Touchpad", items: [ { key: "naturalScroll" }, { key: "scrollFactor" } ] } ] }
    ]

    // ── Search ───────────────────────────────────────────────────────────────
    // Places on the custom pages (no settings list of their own), so search
    // finds them too. target: where on the page (tab / editor), action: run it.
    readonly property var places: [
        { page: "profile", label: "Profile picture", desc: "Shown on the dashboard and lockscreen", keywords: "avatar photo image face", icon: "󰀄" },
        { page: "profile", label: "Display name", keywords: "username greeting hello name", icon: "󰀄" },
        { page: "network", target: "interfaces", label: "Interfaces", desc: "State, addresses, MAC", keywords: "ethernet wifi adapter nic ip address mac eno wlan", icon: "󰈀" },
        { page: "network", target: "interfaces", label: "DHCP or static IP", desc: "Switch an interface between DHCP and a fixed address", keywords: "static ip manual fixed address gateway", icon: "󰩟" },
        { page: "network", target: "interfaces", label: "DHCP lease", desc: "Server, lease time, renew", keywords: "renew expiry lease server", icon: "󰑓" },
        { page: "network", target: "interfaces", label: "Search domain", desc: "Where it comes from (by hand or DHCP)", keywords: "domain suffix dns search", icon: "󰇖" },
        { page: "network", target: "interfaces", label: "Hide virtual interfaces", desc: "Docker, bridges, VMware, …", keywords: "docker veth bridge vmware virtualbox hidden", icon: "󰈉" },
        { page: "network", target: "interfaces", label: "Safe apply", desc: "Revert network changes after 20s unless kept", keywords: "revert rollback undo countdown", icon: "󰕌" },
        { page: "network", target: "interfaces", label: "Wi-Fi on / off", keywords: "wireless radio airplane", icon: "󰖩" },
        { page: "network", target: "profiles", label: "Network profiles", desc: "Saved connections", keywords: "connections nmcli networkmanager", icon: "󰒓" },
        { page: "network", target: "profiles:new", label: "New network profile", keywords: "create add ethernet wifi bridge bond vlan wireguard", icon: "󰐕" },
        { page: "network", target: "profiles", label: "Import a VPN", desc: "OpenVPN or WireGuard file", keywords: "ovpn wireguard openvpn conf", icon: "󰒃" },
        { page: "network", target: "profiles", label: "Wi-Fi password", desc: "Open a Wi-Fi profile → Wi-Fi tab", keywords: "psk security wpa wpa2 wpa3 key", icon: "󰌾" },
        { page: "network", target: "profiles", label: "MTU / MAC address", desc: "Open a profile → its link tab", keywords: "jumbo frames clone spoof random mac", icon: "󰈀" },
        { page: "network", target: "profiles", label: "Static routes", desc: "Open a profile → IPv4 / IPv6 tab", keywords: "route gateway metric", icon: "󰑪" },
        { page: "network", target: "profiles", label: "DHCP server (sharing)", desc: "Profile → IPv4 → Shared", keywords: "share hotspot dnsmasq nat", icon: "󰒍" },
        { page: "network", target: "dns", label: "Global DNS", desc: "Override DNS for every network", keywords: "cloudflare quad9 google adguard 1.1.1.1 8.8.8.8 nameserver", icon: "󰇖" },
        { page: "network", target: "dns", label: "DNS lookup test", keywords: "nslookup dig resolve query test", icon: "󰍉" },
        { page: "network", target: "dns", label: "Flush DNS cache", keywords: "clear cache resolvectl", icon: "󰃢" },
        { page: "network", target: "dns", label: "Hostname", desc: "This computer's name on the network", keywords: "computer name host", icon: "󰒋" },
        { page: "network", target: "hosts", label: "Hosts file", desc: "Remap a name to an IP on this computer", keywords: "etc hosts redirect remap block domain", icon: "󰒋" },
        { page: "monitors", label: "Resolution & refresh rate", keywords: "hz mode screen display", icon: "󰍹" },
        { page: "monitors", label: "Scale & rotation", keywords: "hidpi zoom portrait transform", icon: "󰍹" },
        { page: "monitors", label: "Arrange monitors", keywords: "position layout drag left right primary", icon: "󰍹" },
        { page: "monitors", label: "Variable refresh rate", keywords: "vrr freesync gsync adaptive sync", icon: "󰍹" },
        { page: "keybinds", target: "new", label: "New keybind", keywords: "add create shortcut hotkey", icon: "󰐕" },
        { page: "keybinds", label: "Record keys", desc: "Press a combo to find or create a keybind", keywords: "record capture press", icon: "󰌌" },
        { page: "keybinds", label: "Disable a keybind", keywords: "remove unbind turn off", icon: "󰂭" },
        { page: "autostart", label: "Start a program at login", keywords: "autostart startup boot exec launch", icon: "󰐊" },
        { page: "syntax", label: "Config syntax templates", keywords: "words templates kdl lua option paths rename", icon: "󰅩" },
        { page: "import", label: "Import custom config", keywords: "custom.kdl custom.lua per-device", icon: "󰋺" },
        { action: "export", label: "Export settings", desc: "Save all settings to a file", keywords: "backup save json transfer", icon: "󰈝" },
        { action: "import", label: "Import settings", desc: "Load settings from a file", keywords: "restore load json transfer", icon: "󰋺" }
    ]

    // everything search can find (rebuilt when the pages / binds / profiles change, not per key)
    readonly property var searchIndex: {
        const out = []
        for (const p of visiblePages) {
            out.push({ kind: "page", pageId: p.id, label: p.title, desc: p.desc ?? "", keywords: (p.keywords ?? "") + " page",
                       page: p.group, crumb: p.group, icon: p.icon, boost: 3 })
            for (const s of p.sections ?? []) for (const i of s.items) {
                const sp = fullSpec(p.store, i)
                if (sp.type === "button") continue
                out.push({ kind: "setting", pageId: p.id, store: p.store, key: i.key, spec: sp, label: sp.label,
                           desc: sp.desc ?? "", keywords: sp.keywords ?? "", section: s.title, page: p.title,
                           crumb: p.title + "  ›  " + s.title, icon: p.icon,
                           parentOn: i.dependsOn === undefined || !!valueOf(p.store, i.dependsOn) })
            }
        }
        for (const pl of places) {
            const p = pl.page ? visiblePages.find(x => x.id === pl.page) : null
            if (pl.page && !p) continue
            out.push(Object.assign({ kind: pl.action ? "action" : "place", pageId: pl.page ?? "", page: p?.title ?? "Settings",
                                     crumb: p ? p.title : "Settings", boost: 1 }, pl))
        }
        for (const r of Keybinds.binds)
            out.push({ kind: "keybind", pageId: "keybinds", label: r.desc, desc: r.category,
                       keywords: "keybind " + r.combos.map(c => c.map(k => Keybinds.keyLabel(k)).join(" ") + " " + c.join(" ")).join(" "),
                       page: "Keybinds", crumb: "Keybinds", icon: "󰌌", keys: r.combos[0], bind: r.items[0], boost: -1 })
        for (const c of Network.connections) if (c.type !== "loopback")
            out.push({ kind: "profile", pageId: "network", target: "profile:" + c.uuid, label: c.name,
                       desc: Network.typeLabel(c.type) + (c.active ? "  ·  active on " + c.device : ""),
                       keywords: "network profile connection " + c.type + " " + c.device, page: "Network",
                       crumb: "Network  ›  Profiles", icon: Network.typeIcon(c.type) })
        for (const a of Settings.autostart.items ?? [])
            out.push({ kind: "place", pageId: "autostart", label: a.name, desc: a.cmd, keywords: "autostart startup login",
                       page: "Autostart", crumb: "Autostart", icon: "󰐊" })
        return out
    }
    readonly property var searchVocabulary: SI.vocabularyOf(searchIndex)

    // niri / hyprland stores: their settings service
    function isWm(store) { return store === "niri" || store === "hyprland" }
    function wmFor(store) { return store === "hyprland" ? HyprSettings : NiriSettings }

    function fullSpec(store, item) {
        return isWm(store) ? Object.assign({}, wmFor(store).spec(item.key), item) : item
    }

    // current value of a setting in any store (for dependsOn)
    function valueOf(store, key) {
        if (isWm(store)) return wmFor(store).value(key)
        if (store !== "properties") {
            const v = Settings[store]?.[key]
            if (v !== undefined) return v
            const p = pages.find(p => p.store === store)
            for (const s of p.sections) for (const i of s.items) if (i.key === key) return i.def
            return undefined
        }
        return Properties[key]
    }

    function pageKeys(page) {
        const keys = []
        for (const s of page.sections ?? [])
            for (const i of s.items) keys.push(i.key)
        return keys
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: NiriSettings.windowTitle
            implicitWidth: 980
            implicitHeight: 680
            minimumSize: Qt.size(760, 460)
            color: "transparent"
            visible: true
            // closed by niri (Mod+C) → unload
            onVisibleChanged: if (!visible) root.open = false

            property string query: ""
            readonly property string pageId: root.pageId
            readonly property var page: root.visiblePages.find(p => p.id === pageId) ?? root.visiblePages[0]

            // the page's sections (search shows SearchResults instead)
            readonly property var sections: query.trim() !== "" ? []
                : (page.sections ?? []).map(s => ({ title: s.title, store: page.store, items: s.items }))

            // ranked search results (SettingsSearch.js)
            property int selected: 0
            readonly property var results: {
                const q = query.trim()
                if (q === "") return []
                const toks = SI.tokens(q)
                return root.searchIndex.map((e, i) => ({ entry: e, score: SI.score(e, q, toks), i: i }))
                    .filter(r => r.score > 0)
                    .sort((a, b) => b.score - a.score || a.i - b.i)
                    .slice(0, 60)
            }
            readonly property string suggestion: query.trim() !== "" && results.length === 0 ? SI.suggest(query, root.searchVocabulary) : ""
            onQueryChanged: { selected = 0; flick.contentY = 0 }

            // go to a result
            function openEntry(e) {
                if (!e) return
                if (e.kind === "action") {
                    if (e.action === "export") transfer.exportSettings()
                    else transfer.importSettings()
                    searchField.text = ""
                    return
                }
                if (e.kind === "keybind" && e.bind) root.pendingKeybind = Keybinds.normKeys(e.bind.keys)
                if (e.target) root.pendingAnchor = e.target
                if (e.kind === "setting") root.flashKey = e.store + "." + e.key
                if (e.pageId) root.pageId = e.pageId
                searchField.text = ""
                if (e.kind !== "setting") flick.contentY = 0
            }

            // Ctrl+F or / : search
            Shortcut {
                sequences: [StandardKey.Find, "/"]
                onActivated: { searchField.forceActiveFocus(); searchField.selectAll() }
            }

            Component.onCompleted: { Compositor.settings.refresh(); Network.refresh() }

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: Compositor.appRadius          // same corners as the compositor's windows
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.86)
                // no own border: the compositor draws the window's border (one inside got clipped at the corners)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    // ── Sidebar ───────────────────────────────────────────────
                    Rectangle {
                        Layout.preferredWidth: 230
                        Layout.fillHeight: true
                        radius: Math.max(6, Compositor.appRadius - 2)
                        color: "#27000000"
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            // title, also the drag handle for the window
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 10
                                    Text {
                                        text: "󰒓"
                                        color: Colors.color6
                                        font.pixelSize: 22
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Settings"
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                }
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) bg.Window.window.startSystemMove()
                                }
                            }

                            SearchField {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                implicitHeight: Properties.buttonHeight + 2
                                placeholderText: "Search  (Ctrl+F)"
                                onTextChanged: win.query = text
                                Keys.onEscapePressed: { text = ""; focus = false }
                                Keys.onDownPressed: win.selected = Math.min(win.results.length - 1, win.selected + 1)
                                Keys.onUpPressed: win.selected = Math.max(0, win.selected - 1)
                                Keys.onReturnPressed: win.openEntry(win.results[win.selected]?.entry)
                                Keys.onEnterPressed: win.openEntry(win.results[win.selected]?.entry)
                            }

                            // the tabs scroll when the window is too short for all of them
                            Flickable {
                                id: navFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                // reach into the sidebar padding so the hover scale isn't clipped
                                Layout.leftMargin: -4
                                Layout.rightMargin: -4
                                contentHeight: nav.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                SmoothWheel { flick: navFlick; step: 100 }

                                ColumnLayout {
                                    id: nav
                                    x: 4
                                    width: navFlick.width - 8
                                    spacing: 6

                                    Repeater {
                                        model: ["Shell", "System", "Apps", root.wmGroup]
                                        ColumnLayout {
                                            id: group
                                            required property string modelData
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                Layout.topMargin: 6
                                                Layout.leftMargin: 8
                                                Layout.bottomMargin: 2
                                                text: group.modelData.toUpperCase()
                                                color: Qt.rgba(1, 1, 1, 0.4)
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.letterSpacing: 1.2
                                                font.family: Properties.fontFamily
                                            }

                                            Repeater {
                                                model: root.visiblePages.filter(p => p.group === group.modelData)
                                                NavItem {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    icon: modelData.icon
                                                    label: modelData.title
                                                    selected: win.query === "" && win.pageId === modelData.id
                                                    changes: modelData.custom === "monitors" ? Object.keys(Settings.monitors).length : root.pageKeys(modelData)
                                                        .filter(k => Settings[modelData.store]?.[k] !== undefined).length
                                                    onClicked: { root.pageId = modelData.id; flick.contentY = 0 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 6
                                ActionButton {
                                    Layout.fillWidth: true
                                    icon: "󰈝"
                                    text: "Export"
                                    interactive: transfer.mode !== "busy"
                                    onClicked: transfer.exportSettings()
                                }
                                ActionButton {
                                    Layout.fillWidth: true
                                    icon: "󰋺"
                                    text: "Import"
                                    interactive: transfer.mode !== "busy"
                                    onClicked: transfer.importSettings()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                text: "Changes apply right away (monitors after Apply).\nThe dot marks changed values."
                                color: Qt.rgba(1, 1, 1, 0.35)
                                font.pixelSize: 10
                                font.family: Properties.fontFamily
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Content ───────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // header (drag handle too)
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 56

                            DragHandler {
                                target: null
                                onActiveChanged: if (active) bg.Window.window.startSystemMove()
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: win.query !== "" ? "Search" : win.page.title
                                        color: "white"
                                        font.pixelSize: 24
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        text: win.query !== ""
                                            ? (win.results.length > 0 ? "Results for \"" + win.query.trim() + "\", best first" : "Nothing matches \"" + win.query.trim() + "\"")
                                            : win.page.desc
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: 12
                                        font.family: Properties.fontFamily
                                    }
                                }

                                IconButton {
                                    visible: win.query === "" && !win.page.custom
                                    icon: "󰑓"
                                    tooltip: root.isWm(win.page.store) ? "Reset page to your " + Compositor.name + " config" : "Reset page to defaults"
                                    interactive: root.pageKeys(win.page)
                                        .some(k => Settings[win.page.store ?? "properties"]?.[k] !== undefined)
                                    onClicked: {
                                        for (const k of root.pageKeys(win.page)) {
                                            if (root.isWm(win.page.store)) root.wmFor(win.page.store).reset(k)
                                            else Settings.reset(win.page.store, k)
                                        }
                                    }
                                }
                                IconButton {
                                    icon: "󰅖"
                                    tooltip: "Close"
                                    onClicked: root.open = false
                                }
                            }
                        }

                        // export / import result; an import waits here for confirmation
                        SettingsTransfer {
                            id: transfer
                            Layout.fillWidth: true
                            pages: root.pages
                        }

                        // compositor status: missing include / rejected config
                        Rectangle {
                            id: wmBanner
                            readonly property var svc: root.wmFor(win.page.store)
                            readonly property bool hypr: win.page.store === "hyprland"
                            Layout.fillWidth: true
                            visible: win.query === "" && root.isWm(win.page.store)
                                     && (!svc.included || svc.error !== "" || (hypr && !svc.available))
                            implicitHeight: banner.implicitHeight + 20
                            radius: 14
                            color: Qt.rgba(0.95, 0.55, 0.66, 0.12)
                            border.width: Properties.panelBorderWidth
                            border.color: Qt.rgba(0.95, 0.55, 0.66, 0.35)

                            RowLayout {
                                id: banner
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 14
                                spacing: 10
                                Text {
                                    text: "󰀦"
                                    color: "#f38ba8"
                                    font.pixelSize: 18
                                    font.family: Properties.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: wmBanner.hypr && !wmBanner.svc.available
                                        ? (wmBanner.svc.legacyConfig
                                            ? "Only Hyprland's Lua config (hyprland.lua, Hyprland 0.55+) is supported, this one is hyprland.conf."
                                            : "No Hyprland config found at " + wmBanner.svc.mainConfig)
                                        : !wmBanner.svc.included
                                        ? (wmBanner.hypr
                                            ? "Hyprland doesn't load the settings yet: " + wmBanner.svc.mainConfig
                                              + " needs this as its last line\n" + wmBanner.svc.includeLine
                                            : "niri doesn't load the settings yet: " + wmBanner.svc.mainConfig
                                              + " needs the line\n" + wmBanner.svc.includeLine)
                                        : Compositor.name + " rejected the change, nothing was written:\n" + wmBanner.svc.error
                                    color: "white"
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                IconButton {
                                    visible: wmBanner.svc.included
                                    icon: "󰑓"
                                    tooltip: "Undo all " + Compositor.name + " changes"
                                    onClicked: wmBanner.svc.resetAll()
                                }
                            }
                        }

                        Flickable {
                            id: flick
                            // `pad` of room on every side: buttons grow on hover (up to
                            // ~5px per side) and got cut off at the clip edge. The
                            // flick reaches into the window padding by `pad` and the
                            // content is moved back in by it, so nothing shifts.
                            readonly property int pad: 8
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.leftMargin: -pad
                            Layout.rightMargin: -pad
                            Layout.topMargin: -pad
                            contentHeight: content.implicitHeight + pad * 2
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            // same wheel scrolling as the calendar
                            SmoothWheel { flick: flick; step: 140 }

                            ColumnLayout {
                                id: content
                                x: flick.pad
                                y: flick.pad
                                width: flick.width - flick.pad * 2
                                spacing: 18

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "monitors"
                                    visible: active
                                    sourceComponent: MonitorsPage {}
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "keybinds"
                                    visible: active
                                    sourceComponent: KeybindsPage {
                                        focusKeys: root.pendingKeybind
                                        onFocusConsumed: root.pendingKeybind = ""
                                        anchor: root.pendingAnchor
                                        onAnchorConsumed: root.pendingAnchor = ""
                                    }
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "autostart"
                                    visible: active
                                    sourceComponent: AutostartPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "import"
                                    visible: active
                                    sourceComponent: ImportPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "syntax"
                                    visible: active
                                    sourceComponent: SyntaxPage {}
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "profile"
                                    visible: active
                                    sourceComponent: ProfilePage {}
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "network"
                                    visible: active
                                    sourceComponent: NetworkPage {
                                        footerHost: footerArea
                                        anchor: root.pendingAnchor
                                        onAnchorConsumed: root.pendingAnchor = ""
                                    }
                                }

                                // search
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query.trim() !== ""
                                    visible: active
                                    sourceComponent: SearchResults {
                                        results: win.results
                                        query: win.query
                                        selected: win.selected
                                        flick: flick
                                        suggestion: win.suggestion
                                        pages: root.visiblePages
                                        onActivate: e => win.openEntry(e)
                                        onSuggestionPicked: t => searchField.text = t
                                    }
                                }

                                Repeater {
                                    model: win.sections
                                    ColumnLayout {
                                        id: section
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            Layout.leftMargin: 6
                                            text: section.modelData.title
                                            color: Qt.rgba(1, 1, 1, 0.55)
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: items.implicitHeight
                                            radius: 14
                                            color: "#27000000"
                                            border.width: Properties.panelBorderWidth
                                            border.color: Properties.cardBorder

                                            ColumnLayout {
                                                id: items
                                                width: parent.width
                                                spacing: 0

                                                Repeater {
                                                    model: section.modelData.items
                                                    ColumnLayout {
                                                        id: entry
                                                        required property var modelData
                                                        required property int index
                                                        Layout.fillWidth: true
                                                        spacing: 0

                                                        Rectangle {
                                                            visible: entry.index > 0
                                                            Layout.fillWidth: true
                                                            Layout.leftMargin: 16
                                                            Layout.rightMargin: 16
                                                            implicitHeight: 1
                                                            color: Qt.rgba(1, 1, 1, 0.06)
                                                        }

                                                        // from search: scroll here and flash
                                                        readonly property bool flashMe: root.flashKey !== ""
                                                            && root.flashKey === section.modelData.store + "." + entry.modelData.key
                                                        onFlashMeChanged: if (flashMe) flashTimer.restart()
                                                        Component.onCompleted: if (flashMe) flashTimer.restart()
                                                        Timer {
                                                            id: flashTimer
                                                            interval: 150          // after the page's layout settled
                                                            onTriggered: {
                                                                const y = entry.mapToItem(content, 0, 0).y
                                                                flick.contentY = Math.max(0, Math.min(y - 80, flick.contentHeight - flick.height))
                                                                item.flash()
                                                                root.flashKey = ""
                                                            }
                                                        }

                                                        SettingItem {
                                                            id: item
                                                            Layout.fillWidth: true
                                                            store: section.modelData.store
                                                            spec: root.fullSpec(section.modelData.store, entry.modelData)
                                                            sub: entry.modelData.dependsOn !== undefined
                                                            parentOn: entry.modelData.dependsOn === undefined
                                                                      || !!root.valueOf(section.modelData.store, entry.modelData.dependsOn)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        }

                        // pages put bars here that must stay in reach while scrolling
                        // (network: Apply / keep-or-revert)
                        ColumnLayout {
                            id: footerArea
                            Layout.fillWidth: true
                            Layout.fillHeight: false      // layouts stretch by default; only the content should
                            spacing: 0
                        }
                    }
                }
            }
        }
    }
}
