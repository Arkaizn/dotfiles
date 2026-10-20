pragma Singleton
import Quickshell
import QtQuick

// Which cards the dashboard and the control center show, and where
// (settings app → Shell → Dashboard layout / Control center layout, or live:
// EditMode). Dashboard cards are moved or taken away as a whole. The control
// center has two levels: its cards, and the buttons inside the cards that hold
// buttons (also own cards, filled from `items`).
//
// Stored (only when changed; a missing / broken value = the default):
//   Settings.dashboard:     { columns: [[ids], [ids], [ids]] }
//   Settings.controlCenter: { order: [card ids], custom: { "<id>": { title } },
//                             items: { "<holder id>": [item ids] } }
// Cards that aren't placed anywhere are hidden; own cards stay defined while
// hidden (and after Reset) until deleted.
Singleton {
    id: root

    // ── Dashboard ───────────────────────────────────────────────────────────
    // wide: its column takes the free width (others are 300 px)
    // height: fixed height in its column (0 = share what's left)
    // min: what it needs at least; a column of cards that don't fit makes the dashboard taller
    readonly property var dashCards: [
        { id: "profile",  name: "Profile",       icon: "󰀄", desc: "Picture, name, uptime", wide: false, height: 0, min: 460 },
        { id: "music",    name: "Media player",  icon: "󰎆", desc: "Now playing", wide: true, height: 180, min: 180 },
        { id: "calendar", name: "Calendar",      icon: "󰃭", desc: "Month and the day's events", wide: true, height: 0, min: 270 },
        { id: "stats",    name: "System stats",  icon: "󰓅", desc: "CPU, memory, disks, …", wide: false, height: 0, min: 460 }
    ]
    readonly property var dashIds: dashCards.map(c => c.id)
    function dashCard(id) { return dashCards.find(c => c.id === id) ?? { id: id, name: id, icon: "?", desc: "", wide: false, height: 0, min: 0 } }

    readonly property int dashColumnCount: 3
    readonly property var defaultDashColumns: [["profile"], ["music", "calendar"], ["stats"]]

    function _list(v) {
        // lists that went through a model are list-like, not arrays
        return Array.isArray(v) ? v : v && typeof v === "object" && typeof v.length === "number" ? Array.from(v) : null
    }
    function _copy(v) { return JSON.parse(JSON.stringify(v)) }
    function _same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    // like the niri settings: only what differs from the default is stored
    function _store(group, key, value, def) {
        if (_same(value, def)) Settings.reset(group, key)
        else Settings.set(group, key, value)
    }

    function sanitizeDash(cols) {
        const list = _list(cols)
        if (!list) return null
        const seen = {}, out = []
        for (let i = 0; i < dashColumnCount; i++) {
            const col = _list(list[i]) ?? []
            out.push(col.filter(id => typeof id === "string" && dashIds.includes(id) && !seen[id] && (seen[id] = true)))
        }
        return out
    }

    readonly property var dashColumns: sanitizeDash(Settings.dashboard.columns) ?? defaultDashColumns
    readonly property var dashHidden: dashIds.filter(id => !dashColumns.some(c => c.includes(id)))
    readonly property bool dashChanged: !_same(dashColumns, defaultDashColumns)

    // height the cards need (10 px between cards); the dashboard is at least 460 high inside
    readonly property real dashHeight: Math.max(460, ...dashColumns.map(c =>
        c.reduce((h, id) => h + dashCard(id).min, 0) + Math.max(0, c.length - 1) * 10))

    // a column is wide when it holds a wide card; with none at all every column shares the width
    function dashWide(col) {
        const c = dashColumns[col] ?? []
        const anyWide = dashColumns.some(l => l.some(id => dashCard(id).wide))
        return c.length > 0 && (!anyWide || c.some(id => dashCard(id).wide))
    }

    // move `id` to column `col` at `index` (col < 0 = hide)
    function dashMove(id, col, index) {
        const cols = dashColumns.map(c => c.filter(x => x !== id))
        if (col >= 0 && col < dashColumnCount) {
            const i = Math.max(0, Math.min(index, cols[col].length))
            cols[col].splice(i, 0, id)
        }
        _store("dashboard", "columns", cols, defaultDashColumns)
    }
    function dashRemove(id) { dashMove(id, -1, 0) }
    // back in: the column it is in by default, at the end
    function dashAdd(id) {
        const col = Math.max(0, defaultDashColumns.findIndex(c => c.includes(id)))
        dashMove(id, col, 999)
    }
    function dashReset() { Settings.reset("dashboard", "columns") }

    // ── Control center ──────────────────────────────────────────────────────
    // Two levels, each edited live on its own (EditMode "controlCenter" /
    // "controlCenterButtons"):
    //   cards   — order of the cards (the clock card included)
    //   buttons — which button sits in which card that holds buttons ("holders":
    //             the clock card, Wi-Fi & Bluetooth, tools, own cards)
    readonly property var ccCards: [
        { id: "header",        name: "Clock & power",     icon: "󰥔", desc: "Time, batteries, and buttons" },
        { id: "connectivity",  name: "Wi-Fi & Bluetooth", icon: "󰖩", desc: "Tiles; Wi-Fi / Bluetooth open their list here" },
        { id: "tools",         name: "Tools",             icon: "󰩭", desc: "Screenshot, OCR, record, color picker, capture" },
        { id: "audio",         name: "Volume",            icon: "󰕾", desc: "Output / input volume and devices" },
        { id: "notifications", name: "Notifications",     icon: "󰂚", desc: "Notification list, do not disturb" }
    ]
    readonly property var ccBuiltinIds: ccCards.map(c => c.id)
    readonly property var defaultCcOrder: ["header", "connectivity", "tools", "audio", "notifications"]
    readonly property var ccBuiltinHolders: ["header", "connectivity", "tools"]
    readonly property var defaultCcItems: ({
        header: ["lock", "suspend", "logout", "reboot", "poweroff", "calendar", "perfmon", "keybinds", "settings"],
        connectivity: ["wifi", "bluetooth", "vpn"],
        tools: ["screenshot", "ocr", "record", "color", "capture"]
    })

    // every button (behaviour: modules/controlcenter/CCItem.qml); the clock card
    // shows them as small icon buttons, the other cards as tiles
    readonly property var items: [
        // wide: name + state + buttons in the tile — a card holding one uses at most 2 columns
        { id: "wifi",         name: "Wi-Fi",            icon: "󰤨", desc: "On / off; the tile opens the network list", wide: true },
        { id: "bluetooth",    name: "Bluetooth",        icon: "󰂯", desc: "On / off; the tile opens the device list", wide: true },
        { id: "vpn",          name: "VPN",              icon: "󰖂", desc: "Tailscale / NetBird / VPN profiles; the tile opens the list", wide: true },
        { id: "dnd",          name: "Do not disturb",   icon: "󰂛", desc: "Hold notifications back" },
        { id: "powerprofile", name: "Power profile",    icon: "󰗑", desc: "Cycle saver / balanced / performance" },
        { id: "screenshot",   name: "Screenshot",       icon: "󰩭", desc: "Region" },
        { id: "screenfull",   name: "Full screenshot",  icon: "󰹑", desc: "Whole screen" },
        { id: "ocr",          name: "OCR",              icon: "󰊄", desc: "Region → text" },
        { id: "record",       name: "Record",           icon: "󰕧", desc: "Screen" },
        { id: "color",        name: "Color",            icon: "󰈊", desc: "Pick + copy" },
        { id: "capture",      name: "Capture",          icon: "󰄀", desc: "Screenshot & record menu" },
        { id: "launcher",     name: "Apps",             icon: "󰀻", desc: "App launcher" },
        { id: "clipboard",    name: "Clipboard",        icon: "󰅌", desc: "Clipboard history" },
        { id: "wallpapers",   name: "Wallpapers",       icon: "󰸉", desc: "Wallpaper picker" },
        { id: "connections",  name: "Connections",      icon: "󰣀", desc: "SSH / RDP / VNC" },
        { id: "dashboard",    name: "Dashboard",        icon: "󰕮", desc: "Open the dashboard" },
        { id: "calendar",     name: "Calendar",         icon: "󰃭", desc: "Calendar app" },
        { id: "perfmon",      name: "Performance",      icon: "󰓅", desc: "Performance monitor" },
        { id: "keybinds",     name: "Keybinds",         icon: "󰌌", desc: "Keybind cheatsheet" },
        { id: "settings",     name: "Settings",         icon: "󰒓", desc: "Settings app" },
        { id: "lock",         name: "Lock",             icon: Icons.get("lock"), desc: "Lock the screen" },
        { id: "suspend",      name: "Suspend",          icon: Icons.get("suspend"), desc: "Sleep" },
        { id: "logout",       name: "Log out",          icon: Icons.get("logout"), desc: "Click twice", confirm: true },
        { id: "reboot",       name: "Reboot",           icon: Icons.get("powerReboot"), desc: "Click twice", confirm: true },
        { id: "poweroff",     name: "Shut down",        icon: Icons.get("poweroff"), desc: "Click twice", confirm: true }
    ]
    readonly property var itemIds: items.map(i => i.id)
    function item(id) { return items.find(i => i.id === id) ?? { id: id, name: id, icon: "?", desc: "" } }

    // own cards: { "<id>": { title } }  (older ones kept their tiles in `items` here)
    readonly property var ccCustom: {
        const c = Settings.controlCenter.custom
        const out = {}
        if (c && typeof c === "object" && !Array.isArray(c))
            for (const k in c) {
                const v = c[k]
                if (!v || typeof v !== "object") continue
                out[k] = { title: typeof v.title === "string" ? v.title : "", legacy: _list(v.items) ?? [] }
            }
        return out
    }
    readonly property var ccCustomIds: Object.keys(ccCustom)
    function isCustom(id) { return ccCustom[id] !== undefined }
    function isHolder(id) { return ccBuiltinHolders.includes(id) || isCustom(id) }
    readonly property var ccHolders: ccBuiltinHolders.concat(ccCustomIds)

    function ccCard(id) {
        const b = ccCards.find(c => c.id === id)
        if (b) return b
        const c = ccCustom[id]
        const n = (ccItems[id] ?? []).length
        return { id: id, name: c && c.title !== "" ? c.title : "Own card", icon: "󰆾",
                 desc: n + (n === 1 ? " button" : " buttons"), custom: true }
    }

    // ── cards ──
    readonly property var ccOrder: {
        const l = _list(Settings.controlCenter.order)
        if (!l) return defaultCcOrder
        return l.filter((id, i, a) => typeof id === "string" && (ccBuiltinIds.includes(id) || isCustom(id)) && a.indexOf(id) === i)
    }
    readonly property var ccHidden: ccBuiltinIds.concat(ccCustomIds).filter(id => !ccOrder.includes(id))
    readonly property bool ccChanged: !_same(ccOrder, defaultCcOrder)

    function _setOrder(o) { _store("controlCenter", "order", o, defaultCcOrder) }
    function _setCustom(c) { Settings.set("controlCenter", "custom", c) }

    // move card `id` to `index` (index < 0 = hide)
    function ccMove(id, index) {
        const o = ccOrder.filter(x => x !== id)
        if (index >= 0) o.splice(Math.min(index, o.length), 0, id)
        _setOrder(o)
    }
    function ccRemove(id) { ccMove(id, -1) }
    function ccAdd(id) { ccMove(id, 999) }
    // default order again; own cards are kept (hidden) so nothing is lost
    function ccReset() { Settings.reset("controlCenter", "order") }

    // a new, empty own card at `index` (default: the end); returns its id
    function ccNewCard(index) {
        const id = "card-" + Date.now().toString(36)
        const c = _copy(Settings.controlCenter.custom ?? {})
        c[id] = { title: "" }
        _setCustom(c)
        const o = ccOrder.slice()
        o.splice(index === undefined ? o.length : Math.max(0, Math.min(index, o.length)), 0, id)
        _setOrder(o)
        return id
    }
    // its buttons go back to "not shown"
    function ccDelete(id) {
        if (!isCustom(id)) return
        const m = _itemsCopy()
        delete m[id]
        const c = _copy(Settings.controlCenter.custom ?? {})
        delete c[id]
        _setCustom(c)
        _setItems(m)
        if (ccOrder.includes(id)) _setOrder(ccOrder.filter(x => x !== id))
    }
    function ccRename(id, title) {
        if (!isCustom(id)) return
        const c = _copy(Settings.controlCenter.custom ?? {})
        c[id] = Object.assign({}, c[id], { title: title.trim() })
        _setCustom(c)
    }

    // ── buttons ──
    // holder id → [item ids]; every button sits in one holder at most
    readonly property var ccItems: {
        const stored = Settings.controlCenter.items
        const has = stored && typeof stored === "object" && !Array.isArray(stored)
        const seen = {}, out = {}
        for (const h of ccHolders) {
            const src = has && _list(stored[h]) ? _list(stored[h])
                      : has ? (isCustom(h) ? ccCustom[h].legacy : [])
                      : (defaultCcItems[h] ?? ccCustom[h]?.legacy ?? [])
            out[h] = src.filter(id => typeof id === "string" && itemIds.includes(id) && !seen[id] && (seen[id] = true))
        }
        return out
    }
    readonly property var ccHiddenItems: itemIds.filter(id => !ccHolders.some(h => ccItems[h].includes(id)))
    // the default placement, own cards included (empty)
    readonly property var _defaultItemsAll: {
        const m = _copy(defaultCcItems)
        for (const id of ccCustomIds) m[id] = []
        return m
    }
    readonly property bool ccItemsChanged: !_same(ccItems, _defaultItemsAll)
    function holderOf(itemId) { return ccHolders.find(h => ccItems[h].includes(itemId)) ?? "" }

    function _itemsCopy() { return _copy(ccItems) }
    function _setItems(m) {
        const def = _copy(defaultCcItems)
        for (const id of ccCustomIds) if (m[id] !== undefined) def[id] = []
        _store("controlCenter", "items", m, def)
    }
    // move button `itemId` into `holder` at `index` (holder "" = not shown)
    function ccMoveItem(itemId, holder, index) {
        const m = _itemsCopy()
        for (const h in m) m[h] = m[h].filter(x => x !== itemId)
        if (holder !== "" && m[holder]) m[holder].splice(Math.max(0, Math.min(index, m[holder].length)), 0, itemId)
        _setItems(m)
    }
    function ccRemoveItem(itemId) { ccMoveItem(itemId, "", 0) }
    // every button back where it is by default; own cards end up empty
    function ccResetItems() {
        Settings.reset("controlCenter", "items")
        const c = {}
        for (const id of ccCustomIds) c[id] = { title: ccCustom[id].title }
        _setCustom(c)
    }
}
