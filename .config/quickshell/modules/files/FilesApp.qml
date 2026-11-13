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
//   fresh(path)                  Mod+E: a new tab in the window used last (openFrom "window": a new window) → "ok"
//     select <path>              the same, with it selected → "ok"
//     newWindow <path>           a new window on it → "ok"
//     connect <smb://…|sftp://…>  connect to a server (asks for a password in the window) → "ok"
//     close                      every window · ping → "ok" · isOpen → bool
//     chooserTest <json>         (tests) a dialog as another app would ask for it → its number;
//                                chooserAnswer → what the last one answered (JSON)
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
        onNotice: (text, undoable) => { if (root.owner) root.owner.toast(text, undoable ? "info-undo" : "info") }
        // what an operation made gets selected where its folder is open
        onFinished: (job, res) => {
            const made = (res.made ?? []).map(m => m.dst).filter(d => FmPath.parent(d) === job.dest)
            if (made.length === 0) return
            for (const w of root.windows.concat(root.choosers)) for (const t of w.tabs) if (t.path === job.dest) t.selectSoon(made.map(d => FmPath.base(d)))
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
    // the servers mounted now ([{ uri, path, name }]): the path bar shows their address
    readonly property var serverMounts: (places?.mounts ?? []).filter(m => m.uri && !/^file:/i.test(m.uri) && m.path)
    readonly property var knownServers: {
        const out = servers.slice()
        const add = (uri, name) => { if (!out.some(s => s.uri.replace(/\/$/, "") === uri.replace(/\/$/, ""))) out.push({ uri: uri, name: name }) }
        for (const u of serverHistory) add(u, u.replace(/^[a-z0-9+.-]+:\/\//i, ""))
        // mounted right now (connected here or from another app)
        for (const m of places?.mounts ?? []) if (m.uri && !/^file:/i.test(m.uri)) add(safeUri(m.uri), m.name)
        return out
    }
    function rememberServer(uri, name) {
        uri = safeUri(uri)
        if (servers.some(s => s.uri === uri)) return
        servers = servers.concat([{ uri: uri, name: name || uri.replace(/^[a-z]+:\/\//, "") }]).slice(-50)
        stateObj.set("servers", servers)
    }
    function forgetServer(uri) { servers = servers.filter(s => s.uri !== uri); stateObj.set("servers", servers) }
    // the keyring's saved network logins ([{ id, user, domain, server, protocol, share }], no
    // passwords — the backend reads one only when it's picked): asked again whenever a dialog shows them
    property var logins: []
    function loadLogins() { backendObj.request("logins", {}, { done: res => root.logins = res.logins ?? [], error: () => root.logins = [] }) }
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

    // the view of folders without their own (FmViews): the state's view / sort
    property var viewDefaults: ({ view: (Settings.files.view ?? stateObj.get("view", "list")) === "grid" ? "grid" : "list",
                                  sort: FmViews.sortOf(stateObj.get("sort", {}), { by: "name", reverse: false, dirsFirst: true }) })
    function setViewDefaults(view, sort) {
        viewDefaults = { view: view, sort: sort }
        Settings.set("files", "view", view)
        stateObj.set("sort", sort)
    }
    // the icon size: one per view mode, the same in every folder and window
    // (older per-folder sizes in the state's "folders" are ignored)
    property var iconSizes: {
        const s = stateObj.get("iconSize", {})
        return { list: FmZoom.clamp("list", s.list ?? FmZoom.def.list), grid: FmZoom.clamp("grid", s.grid ?? FmZoom.def.grid) }
    }
    function setIconSize(mode, size) {
        const o = Object.assign({}, iconSizes)
        o[mode] = FmZoom.clamp(mode, size)
        iconSizes = o
        stateObj.set("iconSize", o)
    }
    function viewFor(p) {
        // a folder's old icon size alone doesn't make it a folder with its own view
        const all = stateObj.get("folders", {}), f = all && typeof all === "object" ? all[p] : undefined
        const own = f && typeof f === "object" ? { view: f.view, sort: f.sort } : undefined
        const one = {}
        if (own) one[p] = own
        return FmViews.resolve(one, p, Object.assign({ iconSize: iconSizes }, viewDefaults))
    }
    function rememberView(p, patch) { if (p !== "") stateObj.set("folders", FmViews.remember(stateObj.get("folders", {}), p, patch, Date.now())) }
    function forgetView(p) { stateObj.set("folders", FmViews.forget(stateObj.get("folders", {}), p)) }

    // ── Windows ──
    property var windows: []
    property var lastWindow: null
    readonly property var target: lastWindow ?? windows[windows.length - 1] ?? null
    // the window in front (a dialog too): it shows the operations' questions and messages
    property var front: null
    readonly property var owner: front ?? target

    // ── Other apps' Open / Save dialogs (Settings.files.fileChooser; filesd/portal.py) ──
    property var choosers: []                 // their windows: not in `windows` (never restored, never a target)
    readonly property bool chooserOn: Settings.files.fileChooser ?? false
    onChooserOnChanged: syncChooser()
    function syncChooser() {
        if (!backendObj.ready) return
        backendObj.request("fileChooser", { on: chooserOn }, {
            done: res => { if (res.problem) console.warn("files: file dialogs:", res.problem) }, error: () => {} })
    }
    property string chooserAnswer: ""         // the last answer, as JSON (the chooserAnswer IPC: tests)
    function choose(m) {
        // where it starts: the app's folder (or its file's), else where a dialog was last
        const last = stateObj.get("chooserDir", "")
        const file = typeof m.file === "string" && m.file.startsWith("/") ? m.file : ""
        const dir = m.folder || (file ? FmPath.parent(file) : "") || (typeof last === "string" && last.startsWith("/") ? last : home)
        const w = winComp.createObject(root, { chooser: m, startTabs: [{ path: dir, select: file ? FmPath.base(file) : "" }], startActive: 0 })
        w.finished.connect(() => root.chooserDone(w, false, []))
        choosers = choosers.concat([w])
        if (m.chooser > 0) backendObj.request("chooserAck", { chooser: m.chooser })
        return w
    }
    // the answer (once): to the app, and the window goes
    function chooserDone(w, ok, paths) {
        if (choosers.indexOf(w) < 0) return
        choosers = choosers.filter(x => x !== w)
        if (front === w) front = null
        const m = w.chooser
        const answer = { chooser: m.chooser, ok: ok, paths: paths, choices: w.choiceValues, filter: w.filterIndex }
        chooserAnswer = JSON.stringify(answer)
        if (m.chooser > 0) backendObj.request("chooserDone", answer)
        if (ok && w.tab && w.tab.dir.path.startsWith("/")) stateObj.set("chooserDir", w.tab.dir.path)
        w.visible = false
        Qt.callLater(() => w.destroy())
    }
    // the app took its request back (or the backend handed it to another dialog): no answer
    function chooserGone(n) {
        for (const w of choosers) if (w.chooser.chooser === n) {
            choosers = choosers.filter(x => x !== w)
            if (front === w) front = null
            w.visible = false
            Qt.callLater(() => w.destroy())
        }
    }

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
        if (front === w) front = null
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
        function onReadyChanged() { if (backendObj.ready) { root.refreshPlaces(); root.syncFm1(); root.syncChooser(); root.loadScripts() } }
        function onEvent(m) {
            if (m.event === "places") root.refreshPlaces()
            else if (m.event === "fm1") root.fm1(m)
            else if (m.event === "chooser") root.choose(m)
            else if (m.event === "chooserClosed") root.chooserGone(m.chooser)
        }
        // the backend came back after a crash: the requests it held are gone with it
        function onRestarted() { for (const w of root.choosers.slice()) root.chooserGone(w.chooser.chooser) }
    }

    // org.freedesktop.FileManager1: other apps' "Show in folder" (Settings.files.fileManager1)
    readonly property bool fm1On: Settings.files.fileManager1 ?? true
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

    // an import's file (written by the Settings app a moment ago): read at once
    FileView { id: transferFile; blockLoading: true; printErrors: false }
    function applyTransfer(path, parts) {
        transferFile.path = ""
        transferFile.path = path
        const text = transferFile.text()
        if (text.length > 4194304) return "too big"
        const r = FmTransfer.parse(text)
        if (r.error !== "") return "the file " + r.error
        const doc = r.doc
        const m = FmTransfer.merge({ bookmarks: places.bookmarks ?? [], groups: groups, groupPins: groupPins, servers: servers, starred: starred },
                                   doc, parts, i => "g" + Date.now().toString(36) + i)
        const did = {}
        if (m.bookmarks) {
            // (one after the other: each rewrites GTK's file; a file:// one goes by its path)
            for (const b of m.bookmarks) {
                const p = /^file:/.test(b.uri) ? FmPath.fromArg(b.uri) : ""
                backendObj.request("bookmark", p !== "" ? { action: "add", path: p, label: b.label } : { action: "add", uri: b.uri, label: b.label }, { error: () => {} })
            }
            did.bookmarks = m.bookmarks.length
            did.groups = m.groups.length - groups.length
            saveGroups(m.groups, m.groupPins)
        }
        if (m.servers) { did.servers = m.servers.length - servers.length; servers = m.servers; stateObj.set("servers", servers) }
        if (m.starred) { did.starred = m.starred.length - starred.length; starred = m.starred; stateObj.set("starred", starred) }
        if (m.views) {
            const v = m.views
            if (v.sort) setViewDefaults(viewDefaults.view, FmViews.sortOf(v.sort, viewDefaults.sort))
            if (v.iconSize) for (const mode of ["list", "grid"]) if (typeof v.iconSize[mode] === "number") setIconSize(mode, v.iconSize[mode])
            if (v.columns) setColumns(FmColumns.chosen(v.columns))
            if (v.sideOrder) {
                const known = v.sideOrder.filter(x => sideDefault.indexOf(x) >= 0)
                setSideOrder(known.concat(sideDefault.filter(x => known.indexOf(x) < 0)))
            }
            did.views = true
        }
        return "ok " + JSON.stringify(did)
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
        // Mod+E / the launcher: a new tab in the window used last, or a new window (Settings.files.openFrom)
        function fresh(path: string): string {
            const p = FmPath.fromArg(path)
            if (p === "") return "not an absolute path or file:// URI"
            const w = root.target
            if (!w || (Settings.files.openFrom ?? "tab") === "window") { root.newWindow(p); return "ok" }
            w.newTab(p, {})
            Compositor.focusWindow(w.title)
            return "ok"
        }
        // a server (smb://, sftp://, ftp://, dav(s)://, nfs://): connected to in the window used last
        function connect(uri: string): string {
            if (!/^(smb|sftp|ssh|ftp|ftps|dav|davs|nfs|afp):\/\/\S+$/i.test(uri)) return "not a server address (smb://, sftp://, …)"
            const w = root.target ?? root.newWindow(root.home)
            w.connectTo(uri, false)
            return "ok"
        }
        // Settings → Apps → Files → Export / Import (the Settings app reads / writes the file and
        // the preferences; this process owns the bookmarks and the state): what's here, as JSON
        // ("notready" until the sidebar's places are read, just after a start)
        function transferData(): string {
            if (!root.places) return "notready"
            return JSON.stringify({ bookmarks: (root.places.bookmarks ?? []).map(b => ({ uri: b.uri, label: b.label ?? "" })),
                                    groups: root.groups, groupPins: root.groupPins, servers: root.servers, starred: root.starred,
                                    views: { sort: root.viewDefaults.sort, iconSize: root.iconSizes, columns: root.columns, sideOrder: root.sideOrder } })
        }
        // …and taking one in: `path` a file the Settings app wrote under $XDG_RUNTIME_DIR, `parts`
        // comma-separated (bookmarks, servers, starred, views); answers "ok {what was added}"
        function transferApply(path: string, parts: string): string {
            if (!root.places) return "notready"
            const run = Quickshell.env("XDG_RUNTIME_DIR") ?? ""
            if (run === "" || !path.startsWith(run + "/") || !/^[A-Za-z0-9._\/-]+$/.test(path) || path.includes("/../")) return "not a file of the Settings app"
            return root.applyTransfer(path, parts.split(",").filter(x => FmTransfer.PARTS.indexOf(x) >= 0 && x !== "settings"))
        }
        // tests: a dialog as an app would ask for it ({ mode, multiple, title, filters, … }; its
        // number is negative, nothing goes to the backend), and what the last dialog answered
        function chooserTest(json: string): string {
            let m
            try { m = JSON.parse(json) } catch (e) { return "not JSON" }
            if (!m || typeof m !== "object" || ["open", "save", "folder", "saveFiles"].indexOf(m.mode) < 0) return "mode: open | save | folder | saveFiles"
            const req = { chooser: -Date.now(), mode: m.mode, multiple: m.multiple === true, title: String(m.title ?? "").slice(0, 200),
                          accept: String(m.accept ?? "").slice(0, 200), folder: typeof m.folder === "string" && m.folder.startsWith("/") ? m.folder : "",
                          name: String(m.name ?? "").slice(0, 255), file: typeof m.file === "string" ? m.file : "",
                          files: Array.isArray(m.files) ? m.files.filter(x => typeof x === "string") : [],
                          filters: Array.isArray(m.filters) ? m.filters : [], filter: typeof m.filter === "number" ? m.filter : -1,
                          choices: Array.isArray(m.choices) ? m.choices : [] }
            root.chooserAnswer = ""
            root.choose(req)
            return String(req.chooser)
        }
        function chooserAnswer(): string { return root.chooserAnswer }
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
