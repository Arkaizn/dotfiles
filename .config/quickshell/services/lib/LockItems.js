.pragma library

// What the lockscreen shows (Settings.lockscreen, next to `monitors`): one list
// for the lockscreen itself, its settings page and the settings.json check.
// Every item defaults to on, as before this setting existed.
var items = [          // var: visible as LockItems.items (const isn't)
    { key: "notifications", label: "Notifications", desc: "With their text, only the app and how many (private), or none",
      kind: "choice", def: "full",
      choices: [{ label: "With text", value: "full" }, { label: "Private", value: "private" }, { label: "Off", value: "off" }] },
    { key: "media", label: "Media player", desc: "What's playing", kind: "bool", def: true },
    { key: "mediaControls", label: "Media controls", desc: "Play / pause, skip, seek while locked", kind: "bool", def: true, parent: "media" },
    { key: "seconds", label: "Seconds", desc: "Next to the clock", kind: "bool", def: true },
    { key: "date", label: "Date", desc: "Under the clock", kind: "bool", def: true },
    { key: "hint", label: "\"Press any key\" hint", desc: "", kind: "bool", def: true },
    { key: "avatar", label: "Picture and name", desc: "On the password card", kind: "bool", def: true },
    { key: "lockedSince", label: "\"Locked since\"", desc: "Top left", kind: "bool", def: true },
    { key: "bluetooth", label: "Bluetooth devices", desc: "Connected devices and their battery, top right", kind: "bool", def: true },
    { key: "batteries", label: "Batteries", desc: "Laptop and other batteries, top right", kind: "bool", def: true },
    { key: "power", label: "Power buttons", desc: "Suspend, reboot, shut down without the password", kind: "bool", def: true },
    { key: "blur", label: "Blurred wallpaper", desc: "Off: the wallpaper only dimmed", kind: "bool", def: true }
]

// the settings with the defaults filled in: { key: value }
function resolve(cfg) {
    const o = {}
    for (const it of items) {
        const v = cfg ? cfg[it.key] : undefined
        o[it.key] = it.kind === "bool" ? (typeof v === "boolean" ? v : it.def)
                  : it.choices.some(c => c.value === v) ? v : it.def
    }
    return o
}

// "" when fine, else the message
function check(key, v) {
    const it = items.find(i => i.key === key)
    if (!it) return null                                  // not one of these
    if (it.kind === "bool") return typeof v === "boolean" ? "" : key + " must be true or false"
    return it.choices.some(c => c.value === v) ? "" : key + " is one of " + it.choices.map(c => c.value).join(", ")
}

// ── Login screen (greeter/, Settings.greeter) ──
// By default it follows the lockscreen: the items in `greeterShared` and the
// monitors come from Settings.lockscreen. With follow off it has its own.
// Media, notifications, "locked since" and Bluetooth make no sense before
// login and aren't offered.
var greeterShared = ["seconds", "date", "hint", "avatar", "batteries", "power", "blur"]
var greeterItems = [
    { key: "follow", label: "Same as the lockscreen", desc: "Clock, hint, picture, batteries, power buttons, blur and monitor as set for the lockscreen",
      kind: "bool", def: true },
    { key: "sessionPicker", label: "Session picker", desc: "Choose niri, Hyprland, … on the password card (else the last one used)", kind: "bool", def: true },
    { key: "userPicker", label: "User picker", desc: "Auto: only when there's more than one user",
      kind: "choice", def: "auto",
      choices: [{ label: "Auto", value: "auto" }, { label: "Always", value: "on" }, { label: "Never", value: "off" }] },
    { key: "sync", label: "Keep the login screen's theme up to date", desc: "Colors, wallpaper, fonts and these settings, copied to /var/lib/quickshell-greeter when they change",
      kind: "bool", def: true }
]

// Settings.lockscreen + Settings.greeter → what the login screen does:
// { follow, seconds, date, hint, avatar, batteries, power, blur, monitors: [],
//   sessionPicker, userPicker, sync, defaultUser, defaultSession }
function resolveGreeter(lockCfg, cfg) {
    cfg = cfg || {}
    const own = {}
    for (const it of greeterItems) {
        const v = cfg[it.key]
        own[it.key] = it.kind === "bool" ? (typeof v === "boolean" ? v : it.def)
                    : it.choices.some(c => c.value === v) ? v : it.def
    }
    const shared = resolve(own.follow ? lockCfg : cfg)
    for (const k of greeterShared) own[k] = shared[k]
    const mons = own.follow ? (lockCfg || {}).monitors : cfg.monitors
    own.monitors = Array.isArray(mons) ? mons.filter(m => typeof m === "string" && m !== "") : []
    own.defaultUser = typeof cfg.defaultUser === "string" ? cfg.defaultUser : ""
    own.defaultSession = typeof cfg.defaultSession === "string" ? cfg.defaultSession : ""
    return own
}

// a Settings.greeter key: "" when fine, else the message; null = unknown key
function checkGreeter(key, v) {
    if (greeterShared.includes(key)) return check(key, v)
    const it = greeterItems.find(i => i.key === key)
    if (it) {
        if (it.kind === "bool") return typeof v === "boolean" ? "" : key + " must be true or false"
        return it.choices.some(c => c.value === v) ? "" : key + " is one of " + it.choices.map(c => c.value).join(", ")
    }
    if (key === "monitors")
        return Array.isArray(v) && v.every(x => typeof x === "string" && x.trim() !== "") ? "" : "monitors must be a list of monitor names (\"make model serial\")"
    if (key === "defaultUser")
        return typeof v === "string" && /^([a-z_][a-z0-9_-]{0,31})?$/.test(v) ? "" : "defaultUser is a user name (or empty: you)"
    if (key === "defaultSession")
        return typeof v === "string" && /^[A-Za-z0-9._-]{0,64}$/.test(v) ? "" : "defaultSession is a session file name (or empty: the last one)"
    return null
}
