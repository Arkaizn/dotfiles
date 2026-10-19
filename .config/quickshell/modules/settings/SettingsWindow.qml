import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "network"
import "wm"
import "bar"
import "connections"
import "dotfiles"
import "notifications"
import "theme"
import "audio"
import "bluetooth"
import "power"
import "defaultapps"
import "clipboard"
import "diagnostics"
import "keys"
import "updates"
import "profiles"
import "maintenance"
import "icons"
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
                { key: "fontFamily", type: "font", label: "Font", desc: "A Nerd Font (the icons come from it); used by the bar, popups and widgets" },
                { key: "pixelSize", type: "int", min: 8, max: 24, label: "Text size", desc: "Bar labels and stats" },
                { key: "fontBold", type: "bool", label: "Bold button text" },
                { key: "color", keywords: "text color font colour icon tint", type: "color", label: "Text & icon color", desc: "Buttons, fields and bar icons" } ] },
            { title: "Icons", items: [
                { key: "iconSize", type: "int", min: 10, max: 32, label: "Icon size", desc: "Bar buttons, tray and profile" } ] } ] },

        { id: "icons", group: "Shell", icon: "󰀻", title: "Icons", custom: "icons",
          keywords: "icons icon glyph nerd font change arch logo symbol font family",
          desc: "The shell's Nerd Font, and every icon (click one to change it)" },

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
        { id: "profiles", group: "Shell", icon: "󰆓", title: "Profiles", custom: "profiles",
          keywords: "profile profiles preset snapshot switch work gaming save settings mode",
          desc: "Save settings under a name and switch between them" },
        { id: "theme", group: "Shell", icon: "󰏘", title: "Theme", custom: "theme",
          keywords: "pywal wal colors color scheme palette light dark mode saturation backend saved themes base16",
          desc: "pywal colors: preview, light / dark, saved and built-in themes" },
        { id: "notifications", group: "Shell", icon: "󰂚", title: "Notifications", custom: "notifications",
          keywords: "do not disturb dnd quiet silent schedule night popup position timeout rules mute app test",
          desc: "Do not disturb, popups and per-app rules" },
        { id: "barlayout", group: "Shell", icon: "󰕮", title: "Bar layout", custom: "barlayout",
          keywords: "modules widgets order arrange drag position left right center clock tray workspaces cpu gpu memory temperature",
          desc: "Which modules sit where on the bar, per monitor" },
        { id: "dashlayout", group: "Shell", icon: "󰕮", title: "Dashboard layout", custom: "dashlayout",
          keywords: "dashboard cards columns order arrange drag hide profile music media calendar stats edit live wiggle",
          desc: "Which cards the dashboard shows, in which column" },
        { id: "cclayout", group: "Shell", icon: "󰂚", title: "Control center layout", custom: "cclayout",
          keywords: "control center notification center cards order arrange drag hide own custom card tiles buttons edit live wiggle",
          desc: "Order of its cards, which button sits in which card, own cards" },

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

        { id: "health", group: "Maintenance", icon: "󰓙", title: "Health", custom: "health",
          keywords: "doctor diagnose problems missing packages dependencies check",
          desc: "Is everything the shell needs installed and working?" },

        { id: "defaultapps", group: "Apps", icon: "󰀻", title: "Default apps", custom: "defaultapps",
          keywords: "default application browser file manager editor image viewer video player music pdf email mail archive open with mime xdg",
          desc: "Which app opens links, folders, images, …" },
        { id: "clipboard", group: "Apps", icon: "󰅍", title: "Clipboard", custom: "clipboard",
          keywords: "clipboard history cliphist copy paste pause clear wipe password keepassxc secret",
          desc: "Clipboard history and passwords" },
        { id: "connections", group: "Apps", icon: "󰢹", title: "Connections", custom: "connections",
          keywords: "ssh rdp vnc remote desktop xfreerdp vncviewer server saved hosts",
          desc: "Saved SSH, RDP and VNC connections for the launcher" },
        { id: "audio", group: "System", icon: "󰕾", title: "Audio", custom: "audio",
          keywords: "sound volume speaker headphones microphone mic input output pipewire default device profile hdmi surround mute",
          desc: "Devices, volume limits and sound card profiles" },
        { id: "bluetooth", group: "System", icon: "󰂯", title: "Bluetooth", custom: "bluetooth",
          keywords: "bluetooth adapter paired devices trust block rename forget discoverable visible headphones controller",
          desc: "Adapter and paired devices" },
        { id: "power", group: "System", icon: "󰓅", title: "Power", custom: "power",
          keywords: "power profile performance balanced saver battery energy powerprofilesctl",
          desc: "Power profiles" },
        { id: "updates", group: "Maintenance", icon: "󰚰", title: "Updates", custom: "updates",
          keywords: "updates upgrade pacman yay aur checkupdates pacnew reboot kernel arch news",
          desc: "Pending updates, reboot needed, Arch news, .pacnew files" },
        { id: "cleanup", group: "Maintenance", icon: "󰃢", title: "Cleanup", custom: "cleanup",
          keywords: "cache clean free space orphan packages pacman cache journal crash dumps coredump trash empty",
          desc: "Free space: caches, old packages, logs, trash" },
        { id: "diskusage", group: "Maintenance", icon: "󰋊", title: "Disk usage", custom: "diskusage",
          keywords: "disk usage space ncdu treesize gdu du biggest files folders full",
          desc: "What takes space, folder by folder" },
        { id: "packages", group: "Maintenance", icon: "󰏗", title: "Packages", custom: "packages",
          keywords: "packages installed biggest size aur explicit dependency pacman log history recently unused remove orphans maintenance clean",
          desc: "Package maintenance: unused programs, orphans, biggest, recent changes" },
        { id: "services", group: "Maintenance", icon: "󰒏", title: "Failed services", custom: "services",
          keywords: "systemd failed services units restart reset failed systemctl",
          desc: "Services that failed, with their log" },
        { id: "errorlog", group: "Maintenance", icon: "󰀦", title: "Error log", custom: "errorlog",
          keywords: "journal journalctl errors warnings log boot quickshell log",
          desc: "Errors of this or the last boot" },
        { id: "boottime", group: "Maintenance", icon: "󰑮", title: "Boot time", custom: "boottime",
          keywords: "boot time startup slow systemd-analyze blame critical chain",
          desc: "What slows down booting" },
        { id: "diskhealth", group: "Maintenance", icon: "󰋊", title: "Disk health", custom: "diskhealth",
          keywords: "smart smartctl ssd nvme health wear temperature errors disk",
          desc: "SMART status of your drives" },
        { id: "mirrors", group: "Maintenance", icon: "󰒍", title: "Mirrors", custom: "mirrors",
          keywords: "mirrors mirrorlist reflector pacman download speed",
          desc: "Pacman mirror list: age, refresh with reflector" },
        { id: "dotfiles", group: "Maintenance", icon: "󰊢", title: "Dotfiles", custom: "dotfiles",
          keywords: "git repo sync push pull update backup github rsync check differences",
          desc: "Your dotfiles repo: status, differences with ~/.config, sync scripts" },
        { id: "diagnostics", group: "Maintenance", icon: "󰛳", title: "Network tools", custom: "diagnostics",
          keywords: "ping traceroute port open nc netcat speed test speedtest internet bandwidth latency diagnose network",
          desc: "Ping, traceroute, port check, speed test" },
        { id: "network", group: "System", icon: "󰛳", title: "Network", custom: "network",
          desc: "Interfaces, IP settings, DNS and profiles (NetworkManager)" },

        { id: "keybinds", group: wmGroup, icon: "󰌌", title: "Keybinds", custom: "keybinds",
          desc: "Search, change, disable and add keybinds" },
        { id: "autostart", group: wmGroup, icon: "󰐊", title: "Autostart", custom: "autostart",
          desc: "Programs started at login" },
        { id: "keys", group: "Developer", icon: "󰌆", title: "SSH & GPG", custom: "keys",
          keywords: "ssh key gpg pgp keys fingerprint agent known_hosts passphrase signing git public key",
          desc: "Your keys, agent and known hosts (private keys are never shown)" },
        { id: "syntax", group: "Developer", icon: "󰅩", title: "Syntax", custom: "syntax",
          desc: "How the shell writes the compositor config" },
        { id: "import", group: "Developer", icon: "󰋺", title: "Import custom", custom: "import",
          desc: "Move autostart and keybinds from ~/.config/custom into the settings" },

        { id: "monitors", group: wmGroup, icon: "󰍹", title: "Monitors", custom: "monitors",
          desc: "Arrange screens, resolution, refresh rate and scale" },

        { id: "launcher", group: "Apps", icon: "󰍉", title: "Launcher", store: "launcher",
          keywords: "launcher search calculator qalc math units web search duckduckgo google prefix run command ssh",
          desc: "Calculator and the g / > / ssh prefixes of the app search",
          sections: [
            { title: "In the app search", items: [
                { key: "calculator", type: "bool", def: true, label: "Calculator",
                  desc: "2+2, 5 km to mi, 10 EUR in CHF; =… for anything else (qalc). Enter copies the result" },
                { key: "prefixes", type: "bool", def: true, label: "Prefixes",
                  desc: "g <words> web search · > <program> run in a terminal (no shell) · ssh <name or user@host>" },
                { key: "searchUrl", type: "string", def: "https://duckduckgo.com/?q=%s", label: "Web search address",
                  desc: "%s = what you type, e.g. https://www.google.com/search?q=%s" } ] } ] },
        { id: "perfmon", group: "Apps", icon: "󰓅", title: "Performance monitor", store: "perfmon",
          keywords: "performance monitor cpu gpu temperature fan cooler kraken nzxt cam system monitor",
          desc: "CPU, GPU, memory, liquid cooler, sensors (launcher: Performance Monitor)",
          sections: [
            { title: "Monitor", items: [
                { key: "interval", type: "int", def: 1000, min: 500, max: 5000, step: 250, label: "Update every (ms)",
                  desc: "it only reads anything while its window is open" },
                { key: "open", type: "button", icon: "󰓅", text: "Open", label: "Performance monitor",
                  desc: "also: qs ipc call perfmon toggle", run: () => PerfMon.toggleRequested() } ] } ] },
        { id: "capture", group: "Apps", icon: "󰄀", title: "Screenshots", store: "capture",
          keywords: "screenshot screen capture recording record video grim slurp satty wf-recorder print ocr text recognition tesseract",
          desc: "Screenshots and screen recording (menu: Print, or qs ipc call capture menu)",
          sections: [
            { title: "Screenshots", items: [
                { key: "dir", type: "string", def: "~/Pictures/Screenshots", label: "Folder", desc: "Created if it doesn't exist" },
                { key: "after", type: "choice", def: "save", options: ["save", "copy", "edit"], label: "After taking one",
                  desc: "save: file + clipboard · copy: clipboard only · edit: open in satty" },
                { key: "delay", type: "choice", def: "0", options: ["0", "3", "5", "10"], label: "Delay (seconds)" },
                { key: "pointer", type: "bool", def: false, label: "Include the mouse pointer" },
                { key: "notify", type: "bool", def: true, label: "Notification", desc: "With Open / Edit / Open folder" },
                { key: "ocrLangs", type: "string", def: "eng+deu", label: "Text recognition languages",
                  desc: "tesseract languages joined with + (installed: tesseract --list-langs)" } ] },
            { title: "Recording", items: [
                { key: "videoDir", type: "string", def: "~/Videos/Recordings", label: "Folder" },
                { key: "format", type: "choice", def: "mp4", options: ["mp4", "mkv", "webm"], label: "Format" },
                { key: "audio", type: "choice", def: "both", options: ["both", "desktop", "mic", "none"], label: "Sound",
                  desc: "desktop: what you hear (monitor of the default output) · mic: default input · both: mixed into one track" } ] },
            { title: "Menu", items: [
                { key: "openMenu", type: "button", icon: "󰄀", text: "Open the capture menu", label: "Capture menu",
                  desc: "Keys in the menu: 1 region · 2 screen · 3 window · 4 text (OCR) · 5 record a window · 6 record a screen", run: () => Capture.menuOpen = true } ] } ] },
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
        { page: "barlayout", label: "Add a module to the bar", desc: "CPU, GPU, memory, temperatures, …", keywords: "widget show cpu gpu ram memory temperature stats", icon: "󰐕" },
        { page: "barlayout", label: "Move bar modules", desc: "Drag between left, centre and right", keywords: "order arrange reorder position", icon: "󰕮" },
        { page: "barlayout", label: "Per-monitor bar layout", keywords: "monitor screen output different", icon: "󰍹" },
        { page: "barlayout", label: "Edit the bar live", desc: "Long-press an empty spot of the bar", keywords: "wiggle jiggle drag move icons", icon: "󰏫" },
        { page: "dashlayout", label: "Edit the dashboard live", desc: "Long-press an empty spot of the dashboard", keywords: "wiggle jiggle drag move cards", icon: "󰏫" },
        { page: "cclayout", label: "New control center card", desc: "An own card with tiles of your choice", keywords: "create add custom card tile button", icon: "󰐕" },
        { page: "connections", label: "New SSH / RDP / VNC connection", keywords: "add remote desktop server", icon: "󰐕" },
        { page: "connections", label: "Import connections", desc: "From your scripts and ~/.ssh/config", keywords: "rdp scripts ssh config import", icon: "󰋺" },
        { page: "connections", label: "RDP password in keyring", keywords: "secret-tool password store remote desktop", icon: "󰌋" },
        { page: "dotfiles", label: "Copy config into the dotfiles repo", desc: "push.sh", keywords: "push backup save rsync", icon: "󰕒" },
        { page: "dotfiles", label: "Pull dotfiles", desc: "pull.sh + update.sh", keywords: "pull update git sync", icon: "󰇚" },
        { page: "dotfiles", label: "What differs from the repo", desc: "check.sh", keywords: "diff check changes compare", icon: "󰦒" },
        { page: "notifications", label: "Do not disturb", desc: "Also a schedule, e.g. 22:00 → 07:00", keywords: "dnd quiet mute silence night", icon: "󰂛" },
        { page: "notifications", label: "Notification position", keywords: "popup corner top bottom left right", icon: "󰂚" },
        { page: "notifications", label: "Mute an app's notifications", keywords: "rule silent hide block app", icon: "󰂭" },
        { page: "notifications", label: "Send a test notification", keywords: "test try notify-send", icon: "󰂚" },
        { page: "theme", label: "Light mode", desc: "pywal light scheme from the wallpaper", keywords: "light dark mode bright", icon: "󰖨" },
        { page: "theme", label: "Save the current colors", keywords: "save theme scheme palette", icon: "󰆓" },
        { page: "theme", label: "pywal built-in themes", keywords: "base16 gruvbox nord dracula solarized monokai", icon: "󰏘" },
        { page: "audio", label: "Default audio output", keywords: "speaker headphones sink default device", icon: "󰓃" },
        { page: "audio", label: "Microphone", keywords: "mic input source", icon: "󰍬" },
        { page: "audio", label: "Rename or hide an audio device", keywords: "alias name hide hdmi", icon: "󰏫" },
        { page: "audio", label: "Sound card profile", keywords: "hdmi surround 5.1 stereo off profile", icon: "󰓃" },
        { page: "audio", label: "Volume above 100%", keywords: "boost max volume step scroll", icon: "󰕾" },
        { page: "bluetooth", label: "Bluetooth visible to other devices", keywords: "discoverable pairable visible", icon: "󰂯" },
        { page: "bluetooth", label: "Forget a Bluetooth device", keywords: "unpair remove forget trust block rename", icon: "󰂲" },
        { page: "defaultapps", label: "Default web browser", keywords: "browser firefox zen chrome links", icon: "󰖟" },
        { page: "defaultapps", label: "Default file manager", keywords: "nautilus thunar folders", icon: "󰉋" },
        { page: "defaultapps", label: "Open PDFs / images / videos with", keywords: "pdf image video music player viewer", icon: "󰀻" },
        { page: "clipboard", label: "Pause clipboard history", keywords: "stop clipboard record private", icon: "󰏤" },
        { page: "clipboard", label: "Clear clipboard history", keywords: "wipe delete clipboard", icon: "󰃢" },
        { page: "clipboard", label: "Passwords in the clipboard", keywords: "keepassxc password secret sensitive", icon: "󰌾" },
        { page: "diagnostics", label: "Ping a host", keywords: "ping latency reachable", icon: "󰛳" },
        { page: "diagnostics", label: "Traceroute", keywords: "route hops path", icon: "󰑪" },
        { page: "diagnostics", label: "Check if a port is open", keywords: "port nc netcat firewall", icon: "󰒍" },
        { page: "diagnostics", label: "Internet speed test", keywords: "speedtest bandwidth download upload", icon: "󰓅" },
        { page: "keys", label: "Copy my SSH public key", keywords: "ssh pub key github authorized_keys", icon: "󰆏" },
        { page: "keys", label: "Remove a changed host key", keywords: "known_hosts host identification changed ssh-keygen -R", icon: "󰣀" },
        { page: "keys", label: "New SSH key", keywords: "ssh-keygen generate ed25519", icon: "󰐕" },
        { page: "keys", label: "GPG keys", keywords: "gpg pgp sign expire", icon: "󰌆" },
        { page: "updates", label: "Check for updates", keywords: "pacman yay aur upgrade", icon: "󰚰" },
        { page: "updates", label: ".pacnew files", keywords: "pacdiff pacnew pacsave etc config merge", icon: "󰈙" },
        { page: "profiles", label: "Save settings as a profile", keywords: "profile preset snapshot", icon: "󰆓" },
        { page: "profiles", label: "Switch settings profile", keywords: "profile switch apply work gaming", icon: "󰆓" },
        { page: "cleanup", label: "Free up disk space", keywords: "clean cache full disk space", icon: "󰃢" },
        { page: "cleanup", label: "Remove orphan packages", keywords: "orphans pacman -Qdt unused dependencies", icon: "󰏗" },
        { page: "cleanup", label: "Empty the trash", keywords: "trash bin empty", icon: "󰩹" },
        { page: "diskusage", label: "Biggest files", keywords: "large files big", icon: "󰈔" },
        { page: "mirrors", label: "Refresh pacman mirrors", keywords: "reflector mirrorlist slow downloads", icon: "󰒍" },
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

    // settings profiles (and their IPC) are checked like an import, also while
    // the window was never opened: an invisible checker that exists from the start
    SettingsTransfer {
        id: profileChecker
        visible: false
        pages: root.pages
        Component.onCompleted: SettingsProfiles.validator = s => profileChecker.validate(s, {})
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
                        color: Colors.card
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
                                        color: Colors.ink
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
                                        model: ["Shell", "System", "Maintenance", "Apps", root.wmGroup, "Developer"]   // Developer: config syntax / import, last
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
                                                color: Colors.fade(0.4)
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
                                color: Colors.fade(0.35)
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
                                        color: Colors.ink
                                        font.pixelSize: 24
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        text: win.query !== ""
                                            ? (win.results.length > 0 ? "Results for \"" + win.query.trim() + "\", best first" : "Nothing matches \"" + win.query.trim() + "\"")
                                            : win.page.desc
                                        color: Colors.fade(0.5)
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
                                    color: Colors.red
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
                                    color: Colors.ink
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
                                    active: win.query === "" && win.page.custom === "bluetooth"
                                    visible: active
                                    sourceComponent: BluetoothPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "cleanup"
                                    visible: active
                                    sourceComponent: CleanupPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "diskusage"
                                    visible: active
                                    sourceComponent: DiskUsagePage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "packages"
                                    visible: active
                                    sourceComponent: PackagesPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "services"
                                    visible: active
                                    sourceComponent: ServicesPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "errorlog"
                                    visible: active
                                    sourceComponent: ErrorLogPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "boottime"
                                    visible: active
                                    sourceComponent: BootTimePage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "diskhealth"
                                    visible: active
                                    sourceComponent: DiskHealthPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "mirrors"
                                    visible: active
                                    sourceComponent: MirrorsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "profiles"
                                    visible: active
                                    sourceComponent: ProfilesPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "updates"
                                    visible: active
                                    sourceComponent: UpdatesPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "icons"
                                    visible: active
                                    sourceComponent: IconsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "keys"
                                    visible: active
                                    sourceComponent: KeysPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "diagnostics"
                                    visible: active
                                    sourceComponent: DiagnosticsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "clipboard"
                                    visible: active
                                    sourceComponent: ClipboardPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "defaultapps"
                                    visible: active
                                    sourceComponent: DefaultAppsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "power"
                                    visible: active
                                    sourceComponent: PowerPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "audio"
                                    visible: active
                                    sourceComponent: AudioPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "theme"
                                    visible: active
                                    sourceComponent: ThemePage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "notifications"
                                    visible: active
                                    sourceComponent: NotificationsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "dotfiles"
                                    visible: active
                                    sourceComponent: DotfilesPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "connections"
                                    visible: active
                                    sourceComponent: ConnectionsPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "barlayout"
                                    visible: active
                                    sourceComponent: BarLayoutPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "dashlayout"
                                    visible: active
                                    sourceComponent: DashLayoutPage {}
                                }
                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "cclayout"
                                    visible: active
                                    sourceComponent: CcLayoutPage {}
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "health"
                                    visible: active
                                    sourceComponent: HealthPage {}
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
                                            color: Colors.fade(0.55)
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: items.implicitHeight
                                            radius: 14
                                            color: Colors.card
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
                                                            color: Colors.fade(0.06)
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
