pragma Singleton

import Quickshell
import QtQuick

// Named icons (Nerd Font glyphs) that can be changed in the settings app
// (Shell → Icons). Use `Icons.get("arch")` instead of the glyph itself; it
// gives your choice, else the default below. Bindings that call get() follow
// changes right away.
//
// Settings.icons: { "<id>": "<glyph>" }   (only the changed ones)
Singleton {
    id: root

    // [{ id, label, group, glyph }] — the defaults, in the order the page shows them
    readonly property var list: [
        { group: "Bar", id: "arch", label: "Launcher (Arch logo)", glyph: "󰣇" },
        { group: "Bar", id: "pull", label: "Dotfiles: pull", glyph: "󰇚" },
        { group: "Bar", id: "push", label: "Dotfiles: push", glyph: "󰕒" },
        { group: "Bar", id: "updates", label: "Updates", glyph: "󰅢" },
        { group: "Bar", id: "reboot", label: "Reboot needed", glyph: "󰜉" },
        { group: "Bar", id: "cpuTemp", label: "CPU temperature", glyph: "" },
        { group: "Bar", id: "cpuUsage", label: "CPU usage", glyph: "" },
        { group: "Bar", id: "gpu", label: "GPU", glyph: "󰢮" },
        { group: "Bar", id: "memory", label: "Memory", glyph: "" },
        { group: "Bar", id: "screenshot", label: "Screenshot", glyph: "󰄀" },
        { group: "Bar", id: "recording", label: "Recording", glyph: "󰑊" },
        { group: "Bar", id: "notifications", label: "Notifications", glyph: "󰂚" },
        { group: "Bar", id: "dnd", label: "Do not disturb", glyph: "󰂛" },

        { group: "Media", id: "music", label: "Music", glyph: "󰎇" },
        { group: "Media", id: "play", label: "Play", glyph: "" },
        { group: "Media", id: "pause", label: "Pause", glyph: "" },
        { group: "Media", id: "previous", label: "Previous", glyph: "󰒮" },
        { group: "Media", id: "next", label: "Next", glyph: "󰒭" },
        { group: "Media", id: "mediaRemote", label: "Remote session (mediasync)", glyph: "󰄜" },

        { group: "Volume", id: "volHigh", label: "Loud", glyph: "󰕾" },
        { group: "Volume", id: "volMid", label: "Medium", glyph: "󰖀" },
        { group: "Volume", id: "volLow", label: "Quiet", glyph: "󰕿" },
        { group: "Volume", id: "volMuted", label: "Muted", glyph: "󰝟" },
        { group: "Volume", id: "volNone", label: "No output", glyph: "󰖁" },
        { group: "Volume", id: "headphones", label: "Headphones", glyph: "󰋋" },

        { group: "Network", id: "wired", label: "Wired", glyph: "󰌗" },
        { group: "Network", id: "wifi1", label: "Wi-Fi weak", glyph: "󰤟" },
        { group: "Network", id: "wifi2", label: "Wi-Fi fair", glyph: "󰤢" },
        { group: "Network", id: "wifi3", label: "Wi-Fi good", glyph: "󰤥" },
        { group: "Network", id: "wifi4", label: "Wi-Fi full", glyph: "󰤨" },
        { group: "Network", id: "offline", label: "Offline", glyph: "󰪎" },

        { group: "Battery", id: "batCharging", label: "Charging", glyph: "󰂄" },
        { group: "Battery", id: "bat10", label: "Below 10 %", glyph: "󰁺" },
        { group: "Battery", id: "bat20", label: "Below 20 %", glyph: "󰁻" },
        { group: "Battery", id: "bat40", label: "Below 40 %", glyph: "󰁽" },
        { group: "Battery", id: "bat60", label: "Below 60 %", glyph: "󰁿" },
        { group: "Battery", id: "bat80", label: "Below 80 %", glyph: "󰂁" },
        { group: "Battery", id: "batFull", label: "Full", glyph: "󰁹" },

        { group: "Bluetooth", id: "btOff", label: "Off", glyph: "󰂲" },
        { group: "Bluetooth", id: "btOn", label: "On", glyph: "󰂯" },
        { group: "Bluetooth", id: "btConnected", label: "Connected", glyph: "󰂱" },
        { group: "Bluetooth", id: "btHeadset", label: "Headset / headphones", glyph: "󰋋" },
        { group: "Bluetooth", id: "btSpeaker", label: "Speaker", glyph: "󰓃" },
        { group: "Bluetooth", id: "btController", label: "Controller", glyph: "󰊴" },
        { group: "Bluetooth", id: "btMouse", label: "Mouse", glyph: "󰍽" },
        { group: "Bluetooth", id: "btKeyboard", label: "Keyboard", glyph: "󰌌" },
        { group: "Bluetooth", id: "btTablet", label: "Tablet", glyph: "󰓶" },
        { group: "Bluetooth", id: "btPhone", label: "Phone", glyph: "󰏲" },
        { group: "Bluetooth", id: "btWatch", label: "Watch", glyph: "󰖉" },
        { group: "Bluetooth", id: "btComputer", label: "Computer", glyph: "󰟀" },
        { group: "Bluetooth", id: "btPrinter", label: "Printer", glyph: "󰐪" },
        { group: "Bluetooth", id: "btCamera", label: "Camera", glyph: "󰄀" },

        { group: "Launcher", id: "modeApps", label: "Apps", glyph: "󰀻" },
        { group: "Launcher", id: "modeClipboard", label: "Clipboard", glyph: "󰅍" },
        { group: "Launcher", id: "modeConnections", label: "Connections", glyph: "󰢹" },
        { group: "Launcher", id: "modeWallpapers", label: "Wallpapers", glyph: "󰸉" },
        { group: "Launcher", id: "modeKeybinds", label: "Keybinds", glyph: "󰌌" },

        { group: "Power", id: "lock", label: "Lock", glyph: "󰌾" },
        { group: "Power", id: "suspend", label: "Suspend", glyph: "󰤄" },
        { group: "Power", id: "logout", label: "Log out", glyph: "󰍃" },
        { group: "Power", id: "powerReboot", label: "Reboot", glyph: "󰜉" },
        { group: "Power", id: "poweroff", label: "Shut down", glyph: "󰐥" }
    ]
    readonly property var defaults: {
        const m = {}
        for (const i of list) m[i.id] = i.glyph
        return m
    }
    readonly property var groups: [...new Set(list.map(i => i.group))]

    function get(id) { return Settings.icons[id] || defaults[id] || "" }

    // ── Colored icons ──
    // Some icons get the color of what they do, all over the shell (IconButton,
    // ActionButton, the mail app): trash red, archive blue, star yellow, junk
    // orange. Each color can be turned off (Shell → Icons); a button that sets
    // its own textColor keeps it.
    // Settings.iconColors: { "<id>": false }   (only the turned-off ones)
    //   textColor: Icons.tint(icon, Properties.color)
    readonly property var colorList: [
        { id: "delete", label: "Delete", desc: "Trash cans: delete, remove, forget", color: "red", glyph: "󰆴",
          codes: [0xF01B4, 0xF01B3, 0xF05E8, 0xF05E9, 0xF0683, 0xF06CC, 0xF09E7, 0xF0A79, 0xF0A7A, 0xF0B88, 0xF0B89, 0xF0C62, 0xF0E9D] },
        { id: "archive", label: "Archive", desc: "Archive (mail, …)", color: "blue", glyph: "󰀼",
          codes: [0xF003C, 0xF120E, 0xF1259, 0xF125A] },
        { id: "star", label: "Star", desc: "Starred / favorite, filled or outline", color: "yellow", glyph: "󰓎",
          codes: [0xF04CE, 0xF04D2, 0xF0246, 0xF04D0, 0xF04CF, 0xF09A4] },
        { id: "junk", label: "Junk", desc: "Junk / spam (mail)", color: "orange", glyph: "󰀩",
          codes: [0xF0029, 0xF0CE6] }
    ]
    readonly property var colorByCode: {
        const m = {}
        for (const c of colorList) for (const code of c.codes) m[code] = c.id
        return m
    }
    function colorOn(id) { return Settings.iconColors[id] !== false }
    function setColorOn(id, on) {
        if (on) Settings.reset("iconColors", id)
        else Settings.set("iconColors", id, false)
    }
    function colorOf(id) {
        return id === "delete" ? Colors.red : id === "archive" ? Colors.blue
             : id === "star" ? Colors.yellow : id === "junk" ? Colors.orange : Colors.ink
    }
    // the color for a single glyph, else `fallback` (not one of them, or turned off)
    function tint(glyph, fallback) {
        const g = String(glyph ?? "")
        const id = g.length > 0 && g.length <= 2 ? colorByCode[g.codePointAt(0)] : undefined
        return id && colorOn(id) ? colorOf(id) : fallback
    }
    function set(id, glyph) {
        if (!glyph || glyph === defaults[id]) Settings.reset("icons", id)
        else Settings.set("icons", id, glyph)
    }
}
