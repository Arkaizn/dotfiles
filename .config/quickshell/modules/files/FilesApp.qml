import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib
import "services"
import "lib/FmPath.js" as FmPath
import "lib/FmFormat.js" as FmFormat
import "lib/FmViews.js" as FmViews
import "lib/FmColumns.js" as FmColumns
import "lib/FmZoom.js" as FmZoom

// The file manager (files.qml's own process): the backend, the state file,
// the sidebar's places, the windows (each with its tabs), and what all of them
// share: hidden files on / off, the list's columns, each folder's view, the
// operations (FmOps: jobs, their questions, undo, the clipboard).
//
//   scripts/files/files.sh [path | file:// URI | --select path | --new-window [path]]
//                                                   (starts the process if needed)
//   qs ipc -p ~/.config/quickshell/files.qml call files <fn>:
//     open <path | file://…>     in the window used last: the tab already on it, else a new tab
//                                (a file: its folder, with the file selected); no window, or
//                                Settings.files.openFrom "window": a new one → "ok"
//     select <path>              the same, with it selected → "ok"
//     newWindow <path>           a new window on it → "ok"
//     connect <smb://…|sftp://…>  connect to a server (asks for a password in the window) → "ok"
//     close                      every window · ping → "ok" · isOpen → bool
//     info                       JSON: the last window's current tab { path, count, view, … },
//                                its tabs, and every window's tabs (windows)
// Window titles: "Files — <folder of the current tab>" (the prefix is what window rules and focusing match).
Scope {
    id: root

    // kept across reloads of this process: the windows come back where they were
    PersistentProperties {
        id: persist
        reloadableId: "filesApp"
        property string windowsJson: ""
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string titlePrefix: FmSettings.titlePrefix
    readonly property alias backend: backendObj
    readonly property alias state: stateObj
    property var places: null

    FmBackend { id: backendObj }
    FmState { id: stateObj }
    FmOps {
        id: opsObj
        backend: backendObj
        anyFocused: root.windows.some(w => w.focused)
        // what it has to say goes to the window used last (the one you're looking at)
        onNotice: (text, undoable) => { if (root.target) root.target.toast(text, undoable ? "info-undo" : "info") }
        // what an operation made gets selected where its folder is open
        onFinished: (job, res) => {
            const made = (res.made ?? []).map(m => m.dst).filter(d => FmPath.parent(d) === job.dest)
            if (made.length === 0) return
            for (const w of root.windows) for (const t of w.tabs) if (t.path === job.dest) t.selectSoon(made.map(d => FmPath.base(d)))
        }
    }
    readonly property alias ops: opsObj
    FmThumbs { id: thumbsObj; backend: backendObj }
    readonly property alias thumbs: thumbsObj
    property var dragging: []                 // paths a drag from one of the windows carries

    // ── Starred, saved servers (state file) ──
    property var starred: { const v = stateObj.get("starred", []); return Array.isArray(v) ? v.filter(p => typeof p === "string" && p.startsWith("/")) : [] }
    function isStarred(p) { return starred.indexOf(p) >= 0 }
    function setStarred(paths, on) {
        let list = starred.filter(p => paths.indexOf(p) < 0)
        if (on) list = list.concat(paths)
        starred = list.slice(-1000)
        stateObj.set("starred", starred)
    }
    property var servers: { const v = stateObj.get("servers", []); return Array.isArray(v) ? v.filter(s => s && typeof s.uri === "string") : [] }
    // an address as it may be kept: never a password typed into it (sftp://me:secret@host → sftp://me@host)
    function safeUri(uri) { return String(uri).replace(/^([a-z][a-z0-9+.-]*:\/\/)([^@\/]*?):[^@\/]*@/i, "$1$2@") }
    // every address connected to, newest first (the connect dialog and the address bar offer them);
    // taking a server out of the sidebar keeps it here — "Forget" in the connect dialog takes it out
    property var serverHistory: { const v = stateObj.get("serverHistory", []); return Array.isArray(v) ? v.filter(u => typeof u === "string") : [] }
    function addHistory(uri) {
        const u = safeUri(uri)
        serverHistory = [u].concat(serverHistory.filter(x => x !== u)).slice(0, 50)
        stateObj.set("serverHistory", serverHistory)
    }
    function forgetHistory(uri) { serverHistory = serverHistory.filter(x => x !== uri); stateObj.set("serverHistory", serverHistory) }
    // saved servers, then the history: [{ uri, name }] for suggestions
    readonly property var knownServers: servers.concat(serverHistory.filter(u => !servers.some(s => s.uri === u))
                                                                       .map(u => ({ uri: u, name: u.replace(/^[a-z0-9+.-]+:\/\//i, "") })))
    function rememberServer(uri, name) {
        uri = safeUri(uri)
        if (servers.some(s => s.uri === uri)) return
        servers = servers.concat([{ uri: uri, name: name || uri.replace(/^[a-z]+:\/\//, "") }]).slice(-50)
        stateObj.set("servers", servers)
    }
    function forgetServer(uri) { servers = servers.filter(s => s.uri !== uri); stateObj.set("servers", servers) }
    // ── The sidebar's layout (state file): the top part's order, bookmark groups ──
    readonly property var sideDefault: ["recent", "starred", "home", "desktop", "documents", "downloads", "music", "pictures", "videos", "trash"]
    property var sideOrder: {
        const v = stateObj.get("sideOrder", [])
        const known = (Array.isArray(v) ? v : []).filter(x => sideDefault.indexOf(x) >= 0)
        return known.concat(sideDefault.filter(x => known.indexOf(x) < 0))
    }
    function setSideOrder(list) { sideOrder = list; stateObj.set("sideOrder", list) }
    // groups: [{ id, name, color (a Colors role: red, blue, …, accent), open }]; pins: { bookmark uri: group id }
    property var groups: { const v = stateObj.get("groups", []); return Array.isArray(v) ? v.filter(g => g && typeof g.id === "string" && typeof g.name === "string") : [] }
    property var groupPins: { const v = stateObj.get("groupPins", {}); return v && typeof v === "object" && !Array.isArray(v) ? v : {} }
    function saveGroups(gs, pins) {
        groups = gs
        groupPins = pins
        stateObj.set("groups", gs)
        stateObj.set("groupPins", pins)
    }
    function newGroup(name, uri) {
        const id = "g" + Date.now().toString(36)
        const colors = ["blue", "green", "orange", "chartPurple", "teal", "red", "yellow"]
        const g = { id: id, name: name, color: colors[groups.length % colors.length], open: true }
        const pins = Object.assign({}, groupPins)
        if (uri) pins[uri] = id
        saveGroups(groups.concat([g]), pins)
        return id
    }
    function editGroup(id, patch) { saveGroups(groups.map(g => g.id === id ? Object.assign({}, g, patch) : g), groupPins) }
    // a group goes; its bookmarks stay (at the top level)
    function deleteGroup(id) {
        const pins = {}
        for (const u in groupPins) if (groupPins[u] !== id) pins[u] = groupPins[u]
        saveGroups(groups.filter(g => g.id !== id), pins)
    }
    function pinTo(uri, id) {
        const pins = Object.assign({}, groupPins)
        if (id) pins[uri] = id
        else delete pins[uri]
        saveGroups(groups, pins)
    }
    function moveGroup(id, toId) {
        const list = groups.slice(), i = list.findIndex(g => g.id === id), j = list.findIndex(g => g.id === toId)
        if (i < 0 || j < 0 || i === j) return
        const g = list.splice(i, 1)[0]
        list.splice(j, 0, g)
        saveGroups(list, groupPins)
    }

    // custom actions: executable scripts in ~/.local/share/quickshell/files/scripts (asked again for each menu)
    property var scripts: []
    property string scriptsDir: ""
    function loadScripts(then) {
        backendObj.request("scripts", {}, { done: res => { root.scripts = res.scripts; root.scriptsDir = res.dir; if (then) then() }, error: () => { if (then) then() } })
    }

    function folderName(p) { return p === home ? "Home" : FmFormat.shown(FmPath.base(p)) }

    // ── What every window shares (state file) ──
    // a setting now (Settings.files.hidden); the state file's old value until it's set once
    readonly property bool showHidden: Settings.files.hidden ?? (stateObj.get("hidden", false) === true)
    function setHidden(on) { Settings.set("files", "hidden", on) }
    property var columns: FmColumns.chosen(stateObj.get("columns", undefined))
    function setColumns(ids) { columns = ids; stateObj.set("columns", ids) }

    // the view of folders without their own (FmViews): the state's view / sort / iconSize
    property var viewDefaults: {
        const s = stateObj.get("iconSize", {})
        return { view: (Settings.files.view ?? stateObj.get("view", "list")) === "grid" ? "grid" : "list",
                 sort: FmViews.sortOf(stateObj.get("sort", {}), { by: "name", reverse: false, dirsFirst: true }),
                 iconSize: { list: FmZoom.clamp("list", s.list ?? FmZoom.def.list), grid: FmZoom.clamp("grid", s.grid ?? FmZoom.def.grid) } }
    }
    function setViewDefaults(view, sort, iconSize) {
        viewDefaults = { view: view, sort: sort, iconSize: iconSize }
        Settings.set("files", "view", view)
        stateObj.set("sort", sort)
        stateObj.set("iconSize", iconSize)
    }
    function viewFor(p) { return FmViews.resolve(stateObj.get("folders", {}), p, viewDefaults) }
    function rememberView(p, patch) { if (p !== "") stateObj.set("folders", FmViews.remember(stateObj.get("folders", {}), p, patch, Date.now())) }
    function forgetView(p) { stateObj.set("folders", FmViews.forget(stateObj.get("folders", {}), p)) }

    // ── Windows ──
    property var windows: []
    property var lastWindow: null
    readonly property var target: lastWindow ?? windows[windows.length - 1] ?? null

    Component {
        id: winComp
        FilesWindow { app: root }
    }

    function newWindow(p, select, restore) {
        const w = winComp.createObject(root, {
            startTabs: restore ? restore.tabs : [{ path: p, select: select ?? "" }],
            startActive: restore ? restore.active : 0,
            startSize: restore && restore.width ? { width: restore.width, height: restore.height } : null
        })
        w.finished.connect(() => root._closed(w))
        windows = windows.concat([w])
        lastWindow = w
        saveWindows()
        return w
    }
    // a folder from outside (files.sh, the desktop entry, IPC): into the window used last,
    // or a window of its own (Settings.files.openFrom)
    function show(p, select) {
        const w = target
        if (!w || (Settings.files.openFrom ?? "tab") === "window") { newWindow(p, select); return }
        const i = w.tabOn(p)
        if (i >= 0) {
            w.selectTab(i)
            if (select) w.tab.go(p, { select: select })
        } else {
            w.newTab(p, { select: select ?? "" })
        }
        Compositor.focusWindow(w.title)
    }
    function _closed(w) {
        windows = windows.filter(x => x !== w)
        if (lastWindow === w) lastWindow = windows[windows.length - 1] ?? null
        saveWindows()
        // the last one closed (its close, Ctrl+W, IPC): nothing to reopen after a restart
        if (windows.length === 0) stateObj.flush()
        Qt.callLater(() => w.destroy())
    }
    function closeAll() { for (const w of windows.slice()) w.visible = false }

    // every window's tabs: reopened after a reload (persist) or a restart (state file)
    function saveWindows() {
        const list = windows.map(w => w.describe()).filter(d => d.tabs.length > 0)
        persist.windowsJson = JSON.stringify(list)
        stateObj.set("windows", list)
    }

    // the sidebar's places: asked once the backend runs, again when they change
    function refreshPlaces() { backendObj.request("places", {}, { done: res => root.places = res, error: () => {} }) }
    Connections {
        target: backendObj
        function onReadyChanged() { if (backendObj.ready) { root.refreshPlaces(); root.syncFm1(); root.loadScripts() } }
        function onEvent(m) {
            if (m.event === "places") root.refreshPlaces()
            else if (m.event === "fm1") root.fm1(m)
        }
    }

    // org.freedesktop.FileManager1: other apps' "Show in folder" (Settings.files.fileManager1)
    readonly property bool fm1On: Settings.files.fileManager1 ?? false
    onFm1OnChanged: syncFm1()
    function syncFm1() { if (backendObj.ready) backendObj.request("fileManager1", { on: fm1On }, { error: () => {} }) }
    function fm1(m) {
        const paths = (m.uris ?? []).map(u => FmPath.fromArg(u)).filter(p => p !== "" && p !== "/").slice(0, 20)
        if (m.method === "ShowFolders") for (const p of paths) show(p)
        else if (m.method === "ShowItems" || m.method === "ShowItemProperties") {
            for (const p of paths) show(FmPath.parent(p), FmPath.base(p))
            if (m.method === "ShowItemProperties" && target && paths.length) target.showProps(paths)
        }
    }

    // after a reload / restart (update.sh, a crash): the windows that were open come back
    Component.onCompleted: Qt.callLater(restore)
    function restore() {
        if (windows.length > 0) return
        let raw = null
        if (persist.windowsJson !== "") { try { raw = JSON.parse(persist.windowsJson) } catch (e) {} }
        if (raw === null) raw = stateObj.get("windows", [])
        for (const w of FmViews.windows(raw)) newWindow("", "", w)
    }

    IpcHandler {
        target: "files"
        function open(path: string): string {
            const p = FmPath.fromArg(path)
            if (p === "") return "not an absolute path or file:// URI"
            root.show(p)
            return "ok"
        }
        function select(path: string): string {
            const p = FmPath.fromArg(path)
            if (p === "" || p === "/") return "not an absolute path or file:// URI"
            root.show(FmPath.parent(p), FmPath.base(p))
            return "ok"
        }
        function newWindow(path: string): string {
            const p = FmPath.fromArg(path)
            if (p === "") return "not an absolute path or file:// URI"
            root.newWindow(p)
            return "ok"
        }
        // a server (smb://, sftp://, ftp://, dav(s)://, nfs://): connected to in the window used last
        function connect(uri: string): string {
            if (!/^(smb|sftp|ssh|ftp|ftps|dav|davs|nfs|afp):\/\/\S+$/i.test(uri)) return "not a server address (smb://, sftp://, …)"
            const w = root.target ?? root.newWindow(root.home)
            w.connectTo(uri, false)
            return "ok"
        }
        function close(): void { root.closeAll() }
        function ping(): string { return "ok" }
        function isOpen(): bool { return root.windows.length > 0 }
        function info(): string {
            const w = root.target
            if (!w) return JSON.stringify({ open: false })
            return JSON.stringify(Object.assign(w.info(), { windows: root.windows.map(x => ({ tabs: x.tabs.map(t => t.path), tab: x.current })) }))
        }
    }
}
