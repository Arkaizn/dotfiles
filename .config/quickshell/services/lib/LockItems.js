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
