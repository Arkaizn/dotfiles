.pragma library

// The file manager's settings (Settings.files): one spec list for the
// settings page, the import check and the IPC target that writes them for
// the file manager's own process (services/SettingsStore.qml). Pure: both
// processes load it, neither gets a side effect from it.
//
// An item has the shape of a spec item on a settings page:
//   { key, type: bool | int | choice | string, def, min, max, options }

// the file manager's window titles start with this ("Files — Downloads"): the
// niri window rule (NiriSettings) and focusing match it; FilesApp sets it
var titlePrefix = "Files \u2014 "

// Mod+E (NiriSettings / HyprSettings put it in the generated binds): the file
// manager's launcher, and Nautilus when it can't start (files.sh exits 1).
// A shell command (spawn-sh / exec_cmd); the path is single-quoted.
function launchCommand(shellDir) {
    return "'" + String(shellDir).replace(/'/g, "'\\''") + "/scripts/files/files.sh' || nautilus --new-window"
}

// labels / descriptions: the Settings app's Files page and the app's own
// Preferences show the same (pageSections)
var items = [
    { key: "click", type: "choice", def: "double", options: ["double", "single"], label: "Open items with",
      desc: "double: a click selects, a double-click opens · single: a click opens (Ctrl / Shift click and dragging still select)" },
    { key: "view", type: "choice", def: "list", options: ["list", "grid"], label: "Default view",
      desc: "For folders you haven't set one for (a folder keeps its own view, sort and icon size)" },
    { key: "dirsFirst", type: "bool", def: true, label: "Folders before files", desc: "In every folder, whatever it's sorted by" },
    { key: "hidden", type: "bool", def: false, label: "Show hidden files", desc: "Names starting with a dot, backups (~) · Ctrl+H" },
    { key: "iconTheme", type: "bool", def: false, label: "Use the icon theme's icons",
      desc: "Files, folders and the sidebar with your GTK icon theme instead of the shell's glyphs (a changed theme shows after Files restarts)" },
    { key: "captions", type: "choice", def: "none", options: ["none", "size", "date", "type"], label: "Grid captions",
      desc: "One more line under the names in the grid view" },
    { key: "counts", type: "choice", def: "local", options: ["local", "always", "never"], label: "Count items in folders",
      desc: "Shown in the size column · local: not on network drives (slow there)" },
    { key: "searchDepth", type: "choice", def: "local", options: ["local", "always", "never"], label: "Search in subfolders",
      desc: "local: on this computer's drives, only the open folder on network drives" },
    { key: "thumbs", type: "choice", def: "local", options: ["local", "always", "never"], label: "Thumbnails",
      desc: "Pictures of images, videos, PDFs and documents (the shared ~/.cache/thumbnails) · local: not on network drives" },
    { key: "thumbMax", type: "int", def: 50, min: 1, max: 2000, label: "Thumbnails up to (MB)", desc: "Bigger files get their icon" },
    { key: "executables", type: "choice", def: "ask", options: ["ask", "open", "run"], label: "Executable scripts",
      desc: "When you open one: ask (run, run in a terminal or open as text), open it as text, or run it" },
    { key: "confirmTrash", type: "bool", def: false, label: "Ask before moving to the trash",
      desc: "Deleting for good (Shift+Delete) always asks" },
    { key: "solid", type: "bool", def: false, label: "Solid background", desc: "No transparency behind the files" },
    { key: "sidebarWidth", type: "int", def: 230, min: 180, max: 400, label: "Sidebar width (px)",
      desc: "Or drag the line right of the sidebar; a double-click there resets it" },
    // a folder from another app (files.sh PATH, xdg-open): a tab in the window used last, or a window
    { key: "openFrom", type: "choice", def: "tab", options: ["tab", "window"], label: "Folders from other apps open in",
      desc: "tab: a new tab in the Files window you used last · window: a window of their own" },
    { key: "fileManager1", type: "bool", def: false, label: "Show in folder from other apps",
      desc: "Browsers' and other apps' \"Show in folder\" land in Files instead of Nautilus (it takes the D-Bus name org.freedesktop.FileManager1 and puts a small activation file in ~/.local/share/dbus-1/services; off removes it again)" },
    // the sidebar: what it shows (right-click an entry → Hide; here to bring it back)
    { key: "sideRecent", type: "bool", def: true, label: "Recent" },
    { key: "sideStarred", type: "bool", def: true, label: "Starred" },
    { key: "sideHome", type: "bool", def: true, label: "Home" },
    { key: "sideDesktop", type: "bool", def: true, label: "Desktop" },
    { key: "sideDocuments", type: "bool", def: true, label: "Documents" },
    { key: "sideDownloads", type: "bool", def: true, label: "Downloads" },
    { key: "sideMusic", type: "bool", def: true, label: "Music" },
    { key: "sidePictures", type: "bool", def: true, label: "Pictures" },
    { key: "sideVideos", type: "bool", def: true, label: "Videos" },
    { key: "sideTrash", type: "bool", def: true, label: "Trash" },
    { key: "sideBookmarks", type: "bool", def: true, label: "Bookmarks (section)" },
    { key: "sideDrives", type: "bool", def: true, label: "Drives (section)" },
    { key: "sideNetwork", type: "bool", def: true, label: "Network (section)" }
]

var pageSections = [
    { title: "Browsing", keys: ["click", "view", "dirsFirst", "hidden", "iconTheme", "captions", "counts"] },
    { title: "Search and thumbnails", keys: ["searchDepth", "thumbs", "thumbMax"] },
    { title: "Safety", keys: ["executables", "confirmTrash"] },
    { title: "Window", keys: ["solid", "sidebarWidth", "openFrom"] },
    { title: "Other apps", keys: ["fileManager1"] },
    { title: "Sidebar", keys: ["sideRecent", "sideStarred", "sideHome", "sideDesktop", "sideDocuments", "sideDownloads", "sideMusic", "sidePictures", "sideVideos", "sideTrash", "sideBookmarks", "sideDrives", "sideNetwork"] }
]
// the sections with their items (spec-shaped, for SettingsWindow's `sections`)
function sections() {
    return pageSections.map(function (sec) { return { title: sec.title, items: sec.keys.map(spec) } })
}

// file systems on the network: counts and thumbnails only with "always" there
var networkFs = ["nfs", "nfs4", "cifs", "smb3", "smbfs", "sshfs", "fuse.sshfs", "davfs", "fuse.davfs2",
                 "fuse.gvfsd-fuse", "9p", "afs", "ceph", "glusterfs", "fuse.rclone"]
// "local" | "always" | "never" for a folder on file system fs
function allowed(choice, fs) {
    return choice === "always" || (choice !== "never" && networkFs.indexOf(fs) < 0)
}

function spec(key) {
    for (var i = 0; i < items.length; i++) if (items[i].key === key) return items[i]
    return null
}

// "" when `value` fits the spec of `key`, else what's wrong
function check(key, value) {
    var sp = spec(key)
    if (!sp) return "unknown setting \"" + key + "\""
    var num = typeof value === "number" && isFinite(value)
    switch (sp.type) {
    case "bool":
        return typeof value === "boolean" ? "" : "expected true or false"
    case "int":
        if (!num || Math.floor(value) !== value) return "expected a whole number"
        if (sp.min !== undefined && value < sp.min) return value + " is below the minimum " + sp.min
        if (sp.max !== undefined && value > sp.max) return value + " is above the maximum " + sp.max
        return ""
    case "choice":
        return sp.options.indexOf(value) >= 0 ? "" : JSON.stringify(value) + " isn't one of " + sp.options.join(", ")
    default:
        return typeof value === "string" && value.length <= 4096 ? "" : "expected text"
    }
}

// the whole group (import check): err(path, message) per problem
function validate(group, err) {
    for (var k in group) {
        var m = check(k, group[k])
        if (m !== "") err([k], m)
    }
}

// What the file manager's process may write through the main shell, and
// whether the value is fine. Its own group, its window's zoom, and icons /
// icon colours whose id starts with "files.". `zoomOptions`: AppZoom.options.
// "" = allowed; value undefined = a reset.
function checkRemote(group, key, value, zoomOptions) {
    if (typeof key !== "string" || key === "") return "no key"
    var reset = value === undefined
    if (group === "files") return reset ? (spec(key) ? "" : "unknown setting \"" + key + "\"") : check(key, value)
    if (group === "zoom") {
        if (key !== "files") return "only the file manager's zoom"
        return reset || zoomOptions.indexOf(value) >= 0 ? "" : "zoom must be one of " + zoomOptions.join(", ")
    }
    if (group === "icons" || group === "iconColors") {
        if (!/^files\.[A-Za-z0-9]+$/.test(key)) return "only the file manager's icons"
        if (reset) return ""
        if (group === "icons") return typeof value === "string" && value.length > 0 && value.length <= 8 ? "" : "an icon is one glyph"
        return value === false ? "" : "an icon colour can only be switched off (false)"
    }
    return "the file manager can't change \"" + group + "\""
}
