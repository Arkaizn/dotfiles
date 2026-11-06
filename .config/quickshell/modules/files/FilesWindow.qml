import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath
import "lib/FmColumns.js" as FmColumns
import "lib/FmDrop.js" as FmDrop

// One file manager window: the places sidebar (its width saved like Mail's),
// the path bar, the tabs (FolderTab: a folder each; the strip shows from two
// on), a status line.
//
// Clicks like Nautilus: click selects, Ctrl+click / Shift+click add, double-click opens,
//   middle click: a folder in a new tab · drag on the background: rubber band.
// Keys: ↑/↓/←/→ move (Shift: select along) · PgUp/PgDn · Home/End · Enter open
//   letters: jump to the first name starting with them
//   Ctrl+A select all · Ctrl+Shift+I invert · Ctrl+S select by pattern · Esc select none
//   Alt+↑ / Backspace up · Alt+←/→ back / forward (and the mouse's side buttons) · Alt+Home home
//   Ctrl+T new tab · Ctrl+W close tab · Ctrl+Shift+T reopen it · Ctrl+Tab / Ctrl+PgDn next,
//   Ctrl+Shift+Tab / Ctrl+PgUp previous · Ctrl+Shift+PgUp/PgDn move the tab · Alt+1…9, Alt+0 the n-th
//   Ctrl+N new window · Ctrl+Shift+W / Ctrl+Q close the window
//   Ctrl+H hidden files · Ctrl+1 / Ctrl+2 list / grid · F5 / Ctrl+R reload
//   Ctrl+L type a path (also "/" and "~")
//   Ctrl+C / Ctrl+X / Ctrl+V copy, cut, paste (the clipboard other file managers use too)
//   Ctrl+Z undo · Ctrl+Shift+Z / Ctrl+Y redo · F2 rename · Delete to the trash · Shift+Delete for good
//   Ctrl+Shift+N new folder · Ctrl+M make links
//   typing (or Ctrl+F) searches this folder and below, like Nautilus; Esc goes back
//   Space quick preview · Ctrl+I / Alt+Enter properties · Ctrl+, preferences · Ctrl+D bookmark this folder
//   touchpad: two fingers sideways back / forward, pinch icon size
// Drag files: to a folder, a tab, a sidebar place (on the same drive a move, else a copy;
//   Ctrl: copy, Shift: move, Ctrl+Shift: link — as far as the compositor tells), to other apps (a copy).
//   Ctrl + wheel, Ctrl +/−/0: icon size over the folder, the whole window elsewhere (D0-9)
FloatingWindow {
    id: win

    required property var app            // FilesApp: backend, state, places, views
    property var startTabs: []           // [{ path, select }]
    property int startActive: 0
    property var startSize: null         // { width, height } (restored), else the last window's
    signal finished()                    // the window was closed

    readonly property var backend: app.backend
    readonly property var state: app.state
    readonly property string home: app.home

    // ── Tabs ──
    property var tabs: []                // FolderTab objects, in order
    property int current: 0
    readonly property var tab: tabs[Math.max(0, Math.min(current, tabs.length - 1))] ?? null
    property var closedTabs: []          // [{ path }] for Ctrl+Shift+T, newest last
    readonly property bool zoomKeys: zoomArea.keysOwner === tabHost

    Component { id: tabComp; FolderTab {} }

    // a tab on `p`: after the current one; `background` keeps the current one shown
    function newTab(p, opt) {
        opt = opt ?? {}
        const t = tabComp.createObject(tabHost, { app: app, win: win, startPath: p, startSelect: opt.select ?? "",
                                                  visible: false, width: Qt.binding(() => tabHost.width),
                                                  height: Qt.binding(() => tabHost.height) })
        const at = opt.end ? tabs.length : Math.min(tabs.length, current + 1)
        const list = tabs.slice()
        list.splice(at, 0, t)
        tabs = list
        if (!opt.background || tabs.length === 1) current = at
        else if (at <= current) current++
        _showCurrent()
        app.saveWindows()
        return t
    }
    function closeTab(i) {
        if (i < 0 || i >= tabs.length) return
        if (tabs.length === 1) { win.visible = false; return }
        const t = tabs[i]
        closedTabs = closedTabs.concat([{ path: t.path }]).slice(-10)
        const list = tabs.slice()
        list.splice(i, 1)
        tabs = list
        if (current > i || current >= tabs.length) current = Math.max(0, current - 1)
        _showCurrent()
        t.destroy()
        app.saveWindows()
    }
    function reopenTab() {
        if (closedTabs.length === 0) return
        const c = closedTabs[closedTabs.length - 1]
        closedTabs = closedTabs.slice(0, -1)
        newTab(c.path)
    }
    function selectTab(i) {
        if (i < 0 || i >= tabs.length) return
        const dir = i > current ? 1 : i < current ? -1 : 0
        current = i
        _showCurrent()
        if (dir !== 0) tabs[i].view.enter(dir * Tokens.space.s24)
        if (tabs[i].searching) searchBar.text = tabs[i].query
        app.saveWindows()
    }
    function moveTab(from, to) {
        if (from === to || from < 0 || to < 0 || from >= tabs.length || to >= tabs.length) return
        const list = tabs.slice()
        const t = list.splice(from, 1)[0]
        list.splice(to, 0, t)
        tabs = list
        current = to
        _showCurrent()
        app.saveWindows()
    }
    function _showCurrent() {
        // a tab a drag started from stays (under the new one): hiding it would end the drag
        for (let i = 0; i < tabs.length; i++) {
            tabs[i].visible = i === current || tabs[i].view.draggingOut
            tabs[i].z = i === current ? 1 : 0
        }
        keys.forceActiveFocus()
    }
    // a tab went somewhere else: the title follows, the state file remembers it
    function tabMoved(t) { app.saveWindows() }

    // what restores this window after a restart (FmViews.windows' shape)
    function describe() {
        return { tabs: tabs.map(t => ({ path: t.path || t.startPath })).filter(t => t.path !== ""), active: current,
                 width: Math.round(width), height: Math.round(height) }
    }
    // a tab of this window showing `p`, or -1
    function tabOn(p) { return tabs.findIndex(t => t.path === p) }

    // set before the window maps: niri matches the rules (prefix "Files — ") when it opens
    title: app.titlePrefix + (tab ? tab.title : app.folderName(startTabs[0]?.path ?? home))
    implicitWidth: startSize?.width ?? state.get("window", {}).width ?? 1100
    implicitHeight: startSize?.height ?? state.get("window", {}).height ?? 720
    minimumSize: Qt.size(560, 400)
    color: "transparent"
    visible: true
    onVisibleChanged: if (!visible) finished()
    onWidthChanged: saveSize.restart()
    onHeightChanged: saveSize.restart()
    Timer {
        id: saveSize
        interval: Anim.slower
        onTriggered: { win.state.set("window", { width: Math.round(win.width), height: Math.round(win.height) }); win.app.saveWindows() }
    }

    // the window last used: where folders from outside open (FilesApp.show)
    readonly property bool focused: bg.Window.active
    onFocusedChanged: if (focused) app.lastWindow = win

    // what `qs ipc … call files info` reports (tests, scripts): the current tab, plus the tabs
    function info() {
        return Object.assign({ open: true, title: title, tabs: tabs.map(t => t.path), tab: current }, tab ? tab.info() : {})
    }

    // ── Messages ──
    // tone: "error" (default) · "info" · "info-undo" (an Undo button: the last operation)
    property string message: ""
    property string messageTone: "error"
    function toast(m, tone) { message = m; messageTone = tone ?? "error"; toastTimer.restart() }
    Timer { id: toastTimer; interval: win.messageTone === "error" ? 6000 : 8000; onTriggered: win.message = "" }

    // Nautilus stays as the fallback: a button opens the same folder in it
    property bool haveNautilus: false
    function nautilus() { if (tab) Jobs.detached(["nautilus", "--new-window", "--", tab.path]) }

    Component.onCompleted: {
        const list = startTabs.length ? startTabs : [{ path: home }]
        for (const t of list) newTab(t.path, { select: t.select, end: true, background: true })
        selectTab(Math.max(0, Math.min(startActive, tabs.length - 1)))
        Jobs.which(["nautilus"], have => win.haveNautilus = have.nautilus === true)
    }

    ZoomArea {
        id: zoomArea
        app: "files"
        anchors.fill: parent
        // over the folder the wheel and the keys change its icon size (D0-9);
        // with the pointer away from the window the keys do too (that's where focus is)
        wheelExcept: [tabHost]
        keysExcept: [tabHost]
        keysAway: tabHost

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: Compositor.appRadius / zoomArea.zoom
            // settings: files → solid background (no transparency behind the files)
            color: Colors.alpha(Colors.background, (Settings.files.solid ?? false) ? 1 : 0.86)

            // drags over the tab strip: onto a tab (one drop area for the window, which tab is
            // under the pointer comes from TabStrip.tabAt — the tabs scroll in a Flickable)
            DropArea {
                anchors.fill: parent
                function over(d) {
                    if (!tabStrip.visible) return -1
                    const p = tabStrip.mapFromItem(bg, d.x, d.y)
                    return tabStrip.tabAt(p.x, p.y)
                }
                function track(d) {
                    const i = over(d)
                    if (i !== tabStrip.dropIndex) { tabStrip.dropIndex = i; spring.restart() }
                }
                // taken on entering anywhere (a drop area that refuses the enter gets no moves);
                // only a drop on a tab does something
                onEntered: d => { d.accepted = d.hasUrls || d.hasText; track(d) }
                onPositionChanged: d => track(d)
                onExited: { tabStrip.dropIndex = -1; spring.stop() }
                onDropped: d => {
                    const i = tabStrip.dropIndex
                    tabStrip.dropIndex = -1
                    spring.stop()
                    if (i >= 0) win.handleDrop(d, win.tabs[i].path)
                    else d.accepted = false
                }
                Timer { id: spring; interval: Anim.slower * 2; onTriggered: if (tabStrip.dropIndex >= 0) win.selectTab(tabStrip.dropIndex) }
            }
            // the mouse's back / forward buttons, anywhere in the window
            TapHandler {
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                onTapped: (point, button) => { if (win.tab) button === Qt.BackButton ? win.tab.back() : win.tab.forward() }
            }

            Item {
                id: keys
                focus: true
                Keys.onPressed: event => {
                    const t = win.tab
                    if (address.visible || !t) return
                    const view = t.view
                    const ctrl = event.modifiers & Qt.ControlModifier, alt = event.modifiers & Qt.AltModifier
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0
                    if (ctrl) {
                        switch (event.key) {
                        case Qt.Key_A: view.selectAll(); break
                        case Qt.Key_C: win.app.ops.clip(win.selPaths(), false); break
                        case Qt.Key_X: win.app.ops.clip(win.selPaths(), true); break
                        case Qt.Key_V: win.paste(t.path); break
                        case Qt.Key_Z: if (shift) win.app.ops.redo(); else win.app.ops.undo(); break
                        case Qt.Key_Y: win.app.ops.redo(); break
                        case Qt.Key_M: win.makeLinks(); break
                        case Qt.Key_F: win.startSearch(""); break
                        case Qt.Key_I: if (shift) view.invertSelection(); else win.properties(); break
                        case Qt.Key_Comma: prefs.open(); break
                        case Qt.Key_D: win.bookmark(t.path); break
                        case Qt.Key_S: patternDialog.start(t.folder.count, i => t.folder.at(i)?.name ?? ""); break
                        case Qt.Key_H: win.app.setHidden(!win.app.showHidden); break
                        case Qt.Key_1: t.setView("list"); break
                        case Qt.Key_2: t.setView("grid"); break
                        case Qt.Key_R: t.folder.reload(); break
                        case Qt.Key_L: address.start(); break
                        case Qt.Key_T: if (shift) win.reopenTab(); else win.newTab(t.path); break
                        case Qt.Key_W: if (shift) win.visible = false; else win.closeTab(win.current); break
                        case Qt.Key_Q: win.visible = false; break
                        case Qt.Key_N: if (shift) win.newFolder(); else win.app.newWindow(t.path); break
                        case Qt.Key_Tab: win.selectTab((win.current + 1) % win.tabs.length); break
                        case Qt.Key_Backtab: win.selectTab((win.current - 1 + win.tabs.length) % win.tabs.length); break
                        case Qt.Key_PageDown:
                            if (shift) win.moveTab(win.current, Math.min(win.tabs.length - 1, win.current + 1))
                            else win.selectTab((win.current + 1) % win.tabs.length)
                            break
                        case Qt.Key_PageUp:
                            if (shift) win.moveTab(win.current, Math.max(0, win.current - 1))
                            else win.selectTab((win.current - 1 + win.tabs.length) % win.tabs.length)
                            break
                        default: return
                        }
                        event.accepted = true
                        return
                    }
                    if (alt) {
                        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                            const n = event.key === Qt.Key_0 ? 9 : event.key - Qt.Key_1
                            if (n < win.tabs.length) win.selectTab(n)
                            event.accepted = true
                            return
                        }
                        switch (event.key) {
                        case Qt.Key_Left: t.back(); break
                        case Qt.Key_Right: t.forward(); break
                        case Qt.Key_Up: t.up(); break
                        case Qt.Key_Down: if (view.currentIndex >= 0 && t.folder.at(view.currentIndex)?.dir) t.open(view.currentIndex); break
                        case Qt.Key_Home: t.go(win.home); break
                        case Qt.Key_Return: case Qt.Key_Enter: win.properties(); break
                        default: return
                        }
                        event.accepted = true
                        return
                    }
                    const grid = t.viewMode === "grid"
                    switch (event.key) {
                    case Qt.Key_Down: grid ? view.stepRows(1, shift) : view.step(1, shift); break
                    case Qt.Key_Up: grid ? view.stepRows(-1, shift) : view.step(-1, shift); break
                    case Qt.Key_Right: if (!grid) return; view.step(1, shift); break
                    case Qt.Key_Left: if (!grid) return; view.step(-1, shift); break
                    case Qt.Key_PageDown: view.page(1, shift); break
                    case Qt.Key_PageUp: view.page(-1, shift); break
                    case Qt.Key_Home: view.first(shift); break
                    case Qt.Key_End: view.last(shift); break
                    case Qt.Key_Return: case Qt.Key_Enter: t.activate(view.currentIndex); break
                    case Qt.Key_Backspace: t.up(); break
                    case Qt.Key_F5: t.folder.reload(); break
                    case Qt.Key_F2: win.renameCurrent(); break
                    case Qt.Key_Delete: if (shift) win.deleteSel(); else win.trashSel(); break
                    // (a folder still loading — a slow server —: Esc goes back where you were)
                    case Qt.Key_Escape: if (t.searching) win.endSearch(); else if (t.folder.loading && t.history.length) t.back(); else view.clearSelection(); break
                    case Qt.Key_Space: win.preview(); break
                    default: {
                        // "/" and "~" open the address bar; other text starts a search (like Nautilus)
                        const ch = event.text
                        if (ch.length !== 1 || ch.charCodeAt(0) < 32 || ch.charCodeAt(0) === 127) return
                        if ((ch === "/" || ch === "~") && !t.searching) { address.start(ch); break }
                        win.startSearch(t.searching ? searchBar.text + ch : ch)
                    }
                    }
                    event.accepted = true
                }
            }

            RowLayout {
                id: content
                anchors.fill: parent
                anchors.margins: Tokens.space.s14
                spacing: Tokens.space.s14

                // ── Sidebar ──
                // its width: dragged on the line between it and the folder (Settings.files.sidebarWidth)
                Rectangle {
                    id: side
                    property real dragWidth: -1
                    readonly property real savedWidth: Settings.files.sidebarWidth ?? 230
                    Layout.preferredWidth: Math.max(180, Math.min(dragWidth >= 0 ? dragWidth : savedWidth, 400))
                    Layout.fillHeight: true
                    radius: Math.max(6, Compositor.appRadius - 2)
                    color: Colors.card
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.cardBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.space.s12
                        spacing: Tokens.space.s10

                        AppTitle { icon: FmIcons.g.folder; title: "Files" }

                        Places {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: Tokens.space.s6
                            places: win.app.places
                            path: win.tab ? win.tab.path : ""
                            onPicked: p => { if (win.tab) win.tab.go(p) }
                            servers: win.app.servers
                            app: win.app
                            onMountRequested: v => win.app.ops.mount(v.id, v.name, res => { if (res.path) win.tab.go(res.path) })
                            onEjectRequested: m => {
                                // a tab inside it goes home first (nothing keeps it busy)
                                for (const t of win.tabs) if (m.path && (t.path === m.path || t.path.startsWith(m.path + "/"))) t.go(win.home)
                                win.app.ops.unmount(m.uri, m.name, m.canEject)
                            }
                            onServerPicked: uri => win.connectTo(uri, false)
                            onConnectRequested: connectDialog.open()
                            onDropped: (p, drop) => win.handleDrop(drop, p)
                            onContext: (place, item, x, y) => {
                                // hiding it (Preferences → Sidebar brings it back)
                                const hide = place?.sideKey ? [{ sep: true }, { icon: "\u{F0209}",
                                    label: ["sideBookmarks", "sideDrives", "sideNetwork"].includes(place.sideKey)
                                           ? "Hide this section" : "Hide from the sidebar",
                                    run: () => { Settings.set("files", place.sideKey, false); win.toast("Hidden — Preferences → Sidebar shows it again", "info") } }] : []
                                if (place?.sideKey && !place.path && !place.bookmark) {
                                    menu.show(item, x, y, place.name, [{ icon: FmIcons.g.folderOpen, label: "Open", run: () => win.tab.go(place.sideKey === "sideNetwork" ? "network:" : place.sideKey.slice(4).toLowerCase() + ":") }].concat(hide))
                                    return
                                }
                                // a group header (a bookmark in a group carries its group's id as `group`)
                                if (place?.groupHeader) { win.groupMenu(place.groupHeader, item, x, y); return }
                                if (place?.server) {
                                    menu.show(item, x, y, place.name, [
                                        { icon: "\u{F0318}", label: "Connect", run: () => win.connectTo(place.server, false) },
                                        { icon: "󰆏", label: "Copy address", run: () => win.copy(place.server) },
                                        { icon: FmIcons.g.bookmark, label: "Add to bookmarks", run: () => win.backend.request("bookmark", { action: "add", uri: place.server },
                                              { done: () => win.toast("Bookmarked — a click connects", "info"), error: msg => win.toast(msg) }) },
                                        { sep: true },
                                        { icon: "󰅖", label: "Remove from the sidebar", run: () => win.app.forgetServer(place.server) }])
                                    return
                                }
                                const marks = place.bookmark ? [{ sep: true },
                                    { icon: "\u{F0256}", label: "Move to group…", run: () => win.pinMenu(place, item, x, y) },
                                    { icon: "󰑕", label: "Rename…", run: () => nameDialog.start({ title: "Rename the bookmark", icon: FmIcons.g.bookmark,
                                          name: place.name, action: "Rename", taken: () => false,
                                          run: (n, done) => win.backend.request("bookmark", { action: "rename", uri: place.uri, label: place.path && n === FmPath.base(place.path) ? "" : n },
                                                                                 { done: () => done(""), error: msg => done(msg) }) }) },
                                    { icon: "󰁝", label: "Move up", run: () => win.backend.request("bookmark", { action: "move", uri: place.uri, step: -1 }) },
                                    { icon: "󰁅", label: "Move down", run: () => win.backend.request("bookmark", { action: "move", uri: place.uri, step: 1 }) },
                                    { icon: "󰅖", label: "Remove from bookmarks", run: () => win.backend.request("bookmark", { action: "remove", uri: place.uri }) }] : []
                                // a server bookmark: connect (to the folder in it), and the bookmark's own entries
                                if (place?.bookmark && place.remote) {
                                    menu.show(item, x, y, place.name, [
                                        { icon: "\u{F0318}", label: "Connect", run: () => win.connectTo(place.uri, false) },
                                        { icon: "󰆏", label: "Copy address", run: () => win.copy(place.uri) }].concat(marks, hide))
                                    return
                                }
                                if (!place?.path) return
                                menu.show(item, x, y, place.name ?? FmPath.base(place.path), [
                                    { icon: FmIcons.g.folderOpen, label: "Open", run: () => win.tab.go(place.path) },
                                    { icon: FmIcons.g.tab, label: "Open in new tab", run: () => win.newTab(place.path) },
                                    { icon: FmIcons.g.window, label: "Open in new window", run: () => win.app.newWindow(place.path) },
                                    { icon: "󰆍", label: "Open in terminal", run: () => win.terminal(place.path) }
                                ].concat(place.remote ? [] : [{ icon: FmIcons.g.drive, label: "Disk usage (ncdu)", run: () => win.diskUsage(place.path) }], [
                                    { sep: true },
                                    { icon: "󰆏", label: place.remote ? "Copy address" : "Copy location", run: () => win.copy(place.remote ? place.uri : place.path) }
                                ].concat(place.bookmark ? [] : [
                                    // a mounted server: kept by its address (a click reconnects after a reboot)
                                    { icon: FmIcons.g.bookmark, label: "Add to bookmarks", run: () => backend.request("bookmark",
                                          place.remote ? { action: "add", uri: place.uri, label: place.name } : { action: "add", path: place.path },
                                          { done: () => win.toast("Added to the bookmarks", "info"), error: msg => win.toast(msg) }) }],
                                    marks, hide)))
                            }
                        }
                    }
                }

                // the line between sidebar and folder: drag it to resize, double-click resets
                Item {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 6
                    Layout.leftMargin: -10
                    Layout.rightMargin: -10
                    Rectangle {
                        anchors.centerIn: parent
                        width: 3
                        height: 48
                        radius: 1.5
                        color: Colors.fade(sideSplit.pressed ? 0.7 : sideSplit.containsMouse ? 0.45 : 0)
                        Behavior on color { ColorAnimation { duration: Anim.fast } }
                    }
                    MouseArea {
                        id: sideSplit
                        anchors.fill: parent
                        anchors.leftMargin: -4
                        anchors.rightMargin: -4
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.SizeHorCursor
                        property real startX: 0
                        property real startW: 0
                        onPressed: m => { startX = mapToItem(null, m.x, 0).x; startW = side.width }
                        onPositionChanged: m => { if (pressed) side.dragWidth = Math.max(180, Math.min(400, startW + mapToItem(null, m.x, 0).x - startX)) }
                        onReleased: {
                            if (side.dragWidth >= 0) Settings.set("files", "sidebarWidth", Math.round(side.dragWidth))
                            side.dragWidth = -1
                        }
                        onDoubleClicked: { side.dragWidth = -1; Settings.reset("files", "sidebarWidth") }
                    }
                }

                // ── The folder ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.space.s10

                    RowLayout {
                        id: toolbar
                        Layout.fillWidth: true
                        // one height whatever it shows (path bar, typed path, search field: the
                        // field is a few px taller than the buttons), so the folder never jumps
                        Layout.preferredHeight: Math.max(Tokens.size.control, Properties.buttonHeight + 4)
                        spacing: Tokens.space.s6
                        // a narrow window: the view buttons fold into one menu, the path keeps its room
                        // (searching: its three buttons beside the field need that much more room)
                        readonly property bool narrow: width < Tokens.size.row * (searchBar.visible ? 17 : 14)

                        PathBar {
                            id: pathBar
                            // searching / typing a path: the field takes the crumbs' place, the buttons stay
                            navOnly: address.visible || searchBar.visible
                            mounts: win.app.serverMounts
                            Layout.fillWidth: !navOnly
                            path: win.tab ? win.tab.path : "/"
                            home: win.home
                            specialName: win.tab && win.tab.special !== "" ? win.tab.title : ""
                            canBack: win.tab ? win.tab.history.length > 0 : false
                            canForward: win.tab ? win.tab.future.length > 0 : false
                            onBack: win.tab.back()
                            onForward: win.tab.forward()
                            onUp: win.tab.up()
                            onGo: p => win.tab.go(p)
                            onEditRequested: address.start()
                            readonly property var mark: win.tab ? (win.app.places?.bookmarks ?? []).find(b => b.path === win.tab.path) ?? null : null
                            bookmarked: mark !== null
                            bookmarkable: win.tab ? win.tab.special === "" && win.tab.path.startsWith("/") : false
                            onToggleBookmark: {
                                if (mark) win.backend.request("bookmark", { action: "remove", uri: mark.uri }, { error: msg => win.toast(msg) })
                                else win.bookmark(win.tab.path)
                            }
                        }
                        // searching: the search field takes the path bar's place
                        SearchBar {
                            id: searchBar
                            backdrop: content
                            visible: win.tab?.searching === true
                            Layout.fillWidth: true
                            here: win.tab ? win.tab.title : ""
                            onSearch: (q, opts) => win.tab.search(q, opts)
                            onFinished: win.endSearch()
                            onToResults: { keys.forceActiveFocus(); if (win.tab.view.currentIndex < 0) win.tab.view.first(false) }
                            onOpenFirst: win.openFirstResult()
                        }
                        // Ctrl+L: type a path, with the subfolders offered
                        AddressBar {
                            id: address
                            backdrop: content
                            visible: false
                            Layout.fillWidth: true
                            backend: win.backend
                            here: win.tab ? win.tab.path : "/"
                            home: win.home
                            onGo: p => win.tab.go(p)
                            onConnectUri: uri => address.job = win.connectTo(uri, true)
                            ops: win.app.ops
                            onReveal: p => win.tab.go(FmPath.parent(p), { select: FmPath.base(p) })
                            servers: win.app.knownServers
                            mounts: win.app.serverMounts
                            onFinished: keys.forceActiveFocus()
                        }

                        IconButton {
                            visible: !toolbar.narrow
                            icon: win.app.showHidden ? FmIcons.g.eye : FmIcons.g.eyeOff
                            active: win.app.showHidden
                            tooltip: win.app.showHidden ? "Hide hidden files  (Ctrl+H)" : "Show hidden files  (Ctrl+H)"
                            onClicked: win.app.setHidden(!win.app.showHidden)
                        }
                        // what it's sorted by, said in words: "Name ↑" (a click: the sort menu)
                        ActionButton {
                            id: sortButton
                            visible: !toolbar.narrow
                            readonly property var s: win.tab?.sort ?? { by: "name", reverse: false }
                            readonly property bool best: win.tab ? win.tab.folder !== win.tab.dir && win.tab.folder.relevance === true : false
                            icon: s.reverse ? "\u{F04BD}" : "\u{F04BC}"
                            text: best ? "Best match" : ({ name: "Name", size: "Size", mtime: "Modified", type: "Type" })[s.by] ?? "Sort"
                            tooltip: "Sort by…"
                            onClicked: win.sortMenu(sortButton)
                        }
                        // list or grid, the one shown highlighted (Ctrl+1 / Ctrl+2)
                        Segmented {
                            visible: !toolbar.narrow
                            small: true
                            accessibleName: "View"
                            options: [{ label: "List", value: "list", icon: FmIcons.g.list }, { label: "Grid", value: "grid", icon: FmIcons.g.grid }]
                            value: win.tab?.viewMode ?? "list"
                            onEdited: v => win.tab.setView(v)
                        }
                        JobsButton { ops: win.app.ops; backdrop: content }
                        IconButton {
                            icon: FmIcons.g.cog
                            tooltip: "Preferences  (Ctrl+,)"
                            onClicked: prefs.open()
                        }
                        IconButton {
                            id: viewButton
                            icon: toolbar.narrow ? (win.tab?.viewMode === "grid" ? FmIcons.g.grid : FmIcons.g.list) : FmIcons.g.menu
                            tooltip: toolbar.narrow ? "View and sort" : "More"
                            onClicked: win.viewMenu(viewButton)
                        }
                    }

                    // the backend crashed: say so (it restarts by itself)
                    Banner {
                        visible: win.backend.problem !== ""
                        tone: "error"
                        text: win.backend.problem
                    }

                    TabStrip {
                        id: tabStrip
                        visible: win.tabs.length > 1
                        Layout.fillWidth: true
                        Layout.bottomMargin: -Tokens.space.s4
                        tabs: win.tabs
                        current: win.current
                        onPicked: i => win.selectTab(i)
                        onCloseRequested: i => win.closeTab(i)
                        onMoveRequested: (from, to) => win.moveTab(from, to)
                        onNewRequested: win.newTab(win.tab ? win.tab.path : win.home)
                    }

                    // the tabs' folders: only the current one shows
                    Item {
                        id: tabHost
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    // ── Status line ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.space.s4
                        Layout.rightMargin: Tokens.space.s4
                        spacing: Tokens.space.s10
                        readonly property var view: win.tab ? win.tab.view : null
                        readonly property var folder: win.tab ? win.tab.folder : null
                        // (count: a live change can put another item under the same index)
                        readonly property var cur: view && view.currentIndex >= 0 && folder.count >= 0 ? folder.at(view.currentIndex) : null
                        Text {
                            Layout.fillWidth: true
                            text: {
                                const v = parent.view
                                if (v && v.selCount > 1) {
                                    const sel = v.selectedItems(), files = sel.filter(x => !x.dir)
                                    return sel.length + " selected" + (files.length ? "  ·  " + Format.bytes(files.reduce((a, x) => a + x.size, 0))
                                                                                       + (files.length < sel.length ? " (files)" : "") : "")
                                }
                                const c = parent.cur
                                if (!c) return ""
                                const what = c.dir ? "folder" : Format.bytes(c.size)
                                return "“" + FmFormat.shown(c.name) + "”  ·  " + what + (c.link ? "  ·  link to " + c.target : "")
                            }
                            color: Colors.fade(0.55)
                            font.pixelSize: Tokens.font.caption
                            font.family: Properties.fontFamily
                            elide: Text.ElideMiddle
                            textFormat: Text.PlainText
                        }
                        Text {
                            text: {
                                const f = parent.folder
                                if (!f) return ""
                                if (f.query !== undefined)
                                    return f.loading ? "Searching…  ·  " + f.count + " so far"
                                         : f.count + (f.count === 1 ? " result" : " results") + (f.more ? " (stopped at " + f.count + ")" : "")
                                const parts = []
                                if (!f.loading && f.error === "")
                                    parts.push(f.count + (f.count === 1 ? " item" : " items")
                                               + (f.hiddenCount > 0 && !win.app.showHidden ? " (" + f.hiddenCount + " hidden)" : ""))
                                if (!f.canWrite && f.error === "" && f.kind === undefined) parts.push("read-only")
                                if (f.free >= 0) parts.push(Format.bytes(f.free) + " free")
                                return parts.join("  ·  ")
                            }
                            // with an item under the cursor, the counts give way to its name (all the way when narrow)
                            visible: !(parent.cur && toolbar.narrow)
                            Layout.maximumWidth: parent.cur ? tabHost.width / 2 : tabHost.width
                            elide: Text.ElideLeft
                            color: Colors.fade(0.4)
                            font.pixelSize: Tokens.font.caption
                            font.family: Properties.fontFamily
                            Accessible.role: Accessible.StatusBar
                            Accessible.name: text
                        }
                    }
                }
            }

            // something went wrong (no app for a file, …): rises in, fades out
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.space.s24 + Tokens.space.s20 + (win.message !== "" ? 0 : -Tokens.space.s12)
                Behavior on anchors.bottomMargin { NumberAnimation { duration: Anim.medium; easing.type: Anim.emphasized } }
                opacity: win.message !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                visible: opacity > 0
                width: Math.min(parent.width - 80, errText.implicitWidth + 60 + (win.messageTone === "info-undo" ? Tokens.size.row * 2 : 0))
                height: 40
                radius: height / 2
                color: Colors.surfacePopover
                border.width: Tokens.border.thin
                border.color: win.messageTone === "error" ? Colors.danger : Colors.lineControl
                z: 50
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space.s16
                    anchors.rightMargin: Tokens.space.s6
                    Text { id: errText; Layout.fillWidth: true; text: (win.messageTone === "error" ? FmIcons.g.alert : "󰄬") + "  " + win.message; color: Colors.ink
                           font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight; textFormat: Text.PlainText }
                    ActionButton {
                        visible: win.messageTone === "info-undo" && win.app.ops.canUndo
                        text: "Undo"
                        variant: "ghost"
                        implicitHeight: Tokens.size.controlSmall
                        onClicked: { win.message = ""; win.app.ops.undo() }
                    }
                    IconButton { implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall; icon: "󰅖"; tooltip: "Dismiss"; onClicked: win.message = "" }
                }
            }

            PatternDialog {
                id: patternDialog
                anchors.fill: parent
                z: 60
                onPicked: re => {
                    const n = win.tab.view.selectMatching(re)
                    if (n === 0) win.toast("Nothing matches")
                }
                onClosed: keys.forceActiveFocus()
            }

            NameDialog { id: nameDialog; anchors.fill: parent; z: 60; onClosed: keys.forceActiveFocus() }
            ConfirmDialog { id: confirm; anchors.fill: parent; z: 60; onClosed: keys.forceActiveFocus() }
            FolderPicker { id: picker; anchors.fill: parent; z: 60; backend: win.backend; places: win.app.places; onClosed: keys.forceActiveFocus() }
            PropsDialog { id: props; anchors.fill: parent; z: 60; backend: win.backend; onClosed: keys.forceActiveFocus()
                          onOpenLocation: p => win.tab.go(FmPath.parent(p), { select: FmPath.base(p) }) }
            OpenWithDialog { id: openWith; anchors.fill: parent; z: 60; backend: win.backend; onClosed: keys.forceActiveFocus(); onFailed: msg => win.toast(msg) }
            ConnectDialog { id: connectDialog; anchors.fill: parent; z: 60; known: win.app.knownServers; history: win.app.serverHistory
                            onForget: uri => win.app.forgetHistory(uri); onClosed: keys.forceActiveFocus(); onConnect: (uri, keep) => win.connectTo(uri, keep) }
            CompressDialog { id: compressDialog; anchors.fill: parent; z: 60; onClosed: keys.forceActiveFocus()
                             property var paths: []
                             onCreate: (name, format, password) => win.app.ops.compress(paths, win.tab.path, name, format, password,
                                                                                        res => win.selectIn(win.tab.path, res.path)) }
            // a mount / a server / an archive asks for a password (or a choice)
            PasswordDialog { anchors.fill: parent; z: 70; ops: win.app.ops; mine: win.app.target === win; onClosed: keys.forceActiveFocus() }
            FmPrefs { id: prefs; anchors.fill: parent; z: 60; onClosed: keys.forceActiveFocus() }
            // Space: the selected / current file over the window; ←/→ go through the folder
            FileViewer {
                id: viewer
                spaceCloses: true
                loader: (entry, cb) => win.backend.request("preview", { path: entry.path, type: entry.type }, {
                    done: res => cb(Object.assign({ ok: true }, res)),
                    error: msg => cb({ ok: false, error: msg })
                })
                openDefault: it => win.backend.request("launch", { path: it.path }, { done: res => Compositor.focusLaunched(res.app), error: msg => win.toast(msg) })
                onShownChanged: if (!shown) keys.forceActiveFocus()
            }
            // an operation's questions show in the window used last
            AskDialog { anchors.fill: parent; z: 70; ops: win.app.ops; mine: win.app.target === win; onClosed: keys.forceActiveFocus() }

            PopupMenu { id: menu; parent: bg; backdrop: content; onClosed: win.refocus() }
            // a second menu: what "New document" offers
            PopupMenu { id: subMenu; parent: bg; backdrop: content; onClosed: win.refocus() }
        }
    }

    // ── Menus ──
    // the button that opened the menu, clicked again: it closes (the click outside already closed it)
    property var menuOwner: null
    property real menuClosedAt: 0
    function toggled(item) {
        if (menuOwner === item && Date.now() - menuClosedAt < 400) { menuOwner = null; return true }
        menuOwner = item
        return false
    }
    function sortMenu(item) {
        if (toggled(item)) return
        const t = tab, s = t.sort, mark = by => s.by === by ? "󰄬" : ""
        const searching = t.folder !== t.dir
        menu.show(item, 0, item.height, "Sort", (searching ? [{ icon: t.folder.relevance ? "󰄬" : "", label: "Best match", run: () => t.folder.relevance = true }] : []).concat([
            { icon: mark("name"), label: "Name", run: () => t.setSort({ by: "name", reverse: s.reverse, dirsFirst: s.dirsFirst }) },
            { icon: mark("size"), label: "Size", run: () => t.setSort({ by: "size", reverse: s.reverse, dirsFirst: s.dirsFirst }) },
            { icon: mark("mtime"), label: "Modified", run: () => t.setSort({ by: "mtime", reverse: s.reverse, dirsFirst: s.dirsFirst }) },
            { icon: mark("type"), label: "Type", run: () => t.setSort({ by: "type", reverse: s.reverse, dirsFirst: s.dirsFirst }) },
            { sep: true },
            { icon: s.reverse ? "󰄬" : "", label: "Reversed", run: () => t.setSort({ by: s.by, reverse: !s.reverse, dirsFirst: s.dirsFirst }) },
            { icon: s.dirsFirst ? "󰄬" : "", label: "Folders first", run: () => t.setSort({ by: s.by, reverse: s.reverse, dirsFirst: !s.dirsFirst }) }
        ]))
    }
    // view, hidden files, (narrow: sort), columns, this folder's view
    function viewMenu(item) {
        if (toggled(item)) return
        const t = tab, s = t.sort, tick = on => on ? "󰄬" : ""
        const by = (b, label) => ({ icon: tick(s.by === b), label: "Sort by " + label, run: () => t.setSort({ by: b, reverse: s.reverse, dirsFirst: s.dirsFirst }) })
        const narrow = toolbar.narrow
        menu.show(item, 0, item.height, "View", [].concat(
            narrow ? [{ icon: FmIcons.g.list, label: "List" + (t.viewMode === "list" ? "  ✓" : ""), run: () => t.setView("list") },
                      { icon: FmIcons.g.grid, label: "Grid" + (t.viewMode === "grid" ? "  ✓" : ""), run: () => t.setView("grid") },
                      { icon: tick(app.showHidden), label: "Show hidden files", run: () => app.setHidden(!app.showHidden) },
                      { sep: true },
                      by("name", "name"), by("size", "size"), by("mtime", "modified"), by("type", "type"),
                      { icon: tick(s.reverse), label: "Reversed", run: () => t.setSort({ by: s.by, reverse: !s.reverse, dirsFirst: s.dirsFirst }) },
                      { icon: tick(s.dirsFirst), label: "Folders first", run: () => t.setSort({ by: s.by, reverse: s.reverse, dirsFirst: !s.dirsFirst }) },
                      { sep: true }] : [],
            t.viewMode === "list" ? [{ icon: FmIcons.g.columns, label: "Columns…", run: () => columnMenu("", item, 0, item.height) }] : [],
            [{ icon: "󰒓", label: "Use this view for all folders", run: () => t.makeDefault() }],
            t.ownView ? [{ icon: FmIcons.g.refresh, label: "Reset this folder's view", run: () => t.resetView() }] : [],
            [{ sep: true },
             { icon: "󰒓", label: "Preferences…  (Ctrl+,)", run: () => prefs.open() }],
            haveNautilus ? [{ icon: "\u{F03CC}", label: "Open this folder in Nautilus", run: () => nautilus() }] : []))
    }
    // the list's columns: which ones, their order (right-click on a column head: that one first)
    function columnMenu(id, item, x, y) {
        const ids = app.columns, sp = FmColumns.spec(id)
        const i = ids.indexOf(id)
        menu.show(item, x, y, "Columns", [].concat(
            sp ? [{ icon: "󰁍", label: "Move “" + sp.label + "” left", run: () => app.setColumns(FmColumns.move(ids, id, -1)) },
                  { icon: "󰁔", label: "Move “" + sp.label + "” right", run: () => app.setColumns(FmColumns.move(ids, id, 1)) },
                  { sep: true }].filter((e, k) => k === 2 || (k === 0 ? i > 0 : i < ids.length - 1)) : [],
            FmColumns.all.filter(c => !c.searchOnly).map(c => ({ icon: ids.indexOf(c.id) >= 0 ? "󰄬" : "", label: c.label,
                                      run: () => app.setColumns(FmColumns.toggle(app.columns, c.id)) })),
            [{ sep: true }, { icon: FmIcons.g.refresh, label: "Default columns", run: () => app.setColumns(FmColumns.def.slice()) }]))
    }
    function itemMenu(t, i, item, x, y) {
        const here = t.path, view = t.view
        const local = t.folder === t.dir && FmSettings.allowed("local", t.folder.fs)   // (ncdu: not over the network)
        if (t.special === "trash" || t.special === "network") { viewMenuFor(t, i, item, x, y); return }
        app.loadScripts()                 // (for the next menu: a script added meanwhile shows then)
        if (i < 0) {
            const ro = !t.folder.canWrite
            menu.show(item, x, y, app.folderName(here), [].concat(
                ro ? [] : [{ icon: FmIcons.g.newFolder, label: "New folder…", run: () => win.newFolder() },
                           { icon: FmIcons.g.file, label: "New document…", run: () => win.documentMenu(item, x, y) },
                           { icon: "󰆒", label: "Paste", run: () => win.paste(here) },
                           { sep: true }],
                app.ops.canUndo ? [{ icon: "󰕌", label: "Undo " + app.ops.undoLabel.charAt(0).toLowerCase() + app.ops.undoLabel.slice(1), run: () => app.ops.undo() }] : [],
                app.ops.canRedo ? [{ icon: "󰑎", label: "Redo", run: () => app.ops.redo() }] : [],
                [
                { icon: FmIcons.g.refresh, label: "Reload", run: () => t.folder.reload() },
                { icon: app.showHidden ? FmIcons.g.eyeOff : FmIcons.g.eye, label: app.showHidden ? "Hide hidden files" : "Show hidden files",
                  run: () => app.setHidden(!app.showHidden) },
                { sep: true },
                { icon: FmIcons.g.selectAll, label: "Select all", run: () => view.selectAll() },
                { icon: FmIcons.g.search, label: "Select by pattern…", run: () => patternDialog.start(t.folder.count, k => t.folder.at(k)?.name ?? "") },
                { sep: true },
                { icon: FmIcons.g.tab, label: "Open in new tab", run: () => win.newTab(here) },
                { icon: "󰆍", label: "Open in terminal", run: () => win.terminal(here) },
            ].concat(local ? [{ icon: FmIcons.g.drive, label: "Disk usage (ncdu)", run: () => win.diskUsage(here) }] : [], [
                { icon: "󰆏", label: "Copy location", run: () => win.copy(here) },
                { icon: FmIcons.g.bookmark, label: "Add to bookmarks  (Ctrl+D)", run: () => win.bookmark(here) },
                { icon: "󰋽", label: "Properties", run: () => props.start([here]) }
            ])))
            return
        }
        const it = t.folder.at(i)
        if (!it) return
        if (view.selCount > 1 && view.selection[it.key]) {
            const sel = view.selectedItems()
            const paths = sel.map(x => t.folder.pathOf(x))
            menu.show(item, x, y, sel.length + " items", [
                { icon: FmIcons.g.folderOpen, label: "Open all", run: () => t.activate(i) },
                { sep: true },
                { icon: "󰆐", label: "Cut", run: () => app.ops.clip(paths, true) },
                { icon: "󰆏", label: "Copy", run: () => app.ops.clip(paths, false) },
                { icon: "󰪹", label: "Copy to…", run: () => win.copyTo(paths, "copy") },
                { icon: "󰪹", label: "Move to…", run: () => win.copyTo(paths, "move") },
                { icon: FmIcons.g.link, label: "Make links", run: () => win.makeLinks() },
                { icon: "\u{F05C4}", label: "Compress…", run: () => win.compress(paths) },
                { icon: "\u{F04CE}", label: paths.every(q => app.isStarred(q)) ? "Unstar" : "Star", run: () => app.setStarred(paths, !paths.every(q => app.isStarred(q))) }
            ].concat(app.scripts.length ? [{ icon: "\u{F018D}", label: "Scripts…", run: () => win.scriptsMenu(paths, item, x, y) }] : [], [
                { icon: FmIcons.g.trash, label: "Move to the trash", run: () => win.trashSel() },
                { icon: FmIcons.g.alert, label: "Delete for good…", danger: true, run: () => win.deleteSel() },
                { sep: true },
                { icon: FmIcons.g.selectAll, label: "Invert selection", run: () => view.invertSelection() },
                { icon: "󰆏", label: "Copy paths", run: () => win.copy(paths.join("\n")) },
                { icon: "󰋽", label: "Properties", run: () => win.properties() },
                { icon: "󰆏", label: "Copy names", run: () => win.copy(sel.map(x => x.name).join("\n")) }
            ]))
            return
        }
        const p = t.folder.pathOf(it)
        menu.show(item, x, y, it.name, [].concat(
            [{ icon: it.dir ? FmIcons.g.folderOpen : FmIcons.item(it), label: it.dir ? "Open" : "Open with default app", run: () => t.open(i) }],
            !it.dir ? [{ icon: "󰀻", label: "Open with…", run: () => openWith.start([p], it.type) },
                       { icon: "󰈈", label: "Quick look  (Space)", run: () => win.preview() }] : [],
            t.folder !== t.dir ? [{ icon: FmIcons.g.folder, label: "Open item location", run: () => t.openLocation(i) }] : [],
            it.dir ? [{ icon: FmIcons.g.bookmark, label: "Add to bookmarks", run: () => win.bookmark(p) },
                      { icon: FmIcons.g.tab, label: "Open in new tab", run: () => win.newTab(p, { background: true }) },
                      { icon: FmIcons.g.window, label: "Open in new window", run: () => app.newWindow(p) },
                      { icon: "󰆍", label: "Open in terminal", run: () => win.terminal(p) }] : [],
            it.dir && local ? [{ icon: FmIcons.g.drive, label: "Disk usage (ncdu)", run: () => win.diskUsage(p) }] : [],
            // a script: run in a terminal that stays open (a double-click only opens it as text)
            !it.dir && isScript(it) ? [{ icon: "\u{F018D}", label: it.exec ? "Run in terminal" : "Allow and run in terminal",
                                         run: () => win.runInTerminal(p, it) }] : [],
            !it.dir && it.exec && !isScript(it) ? [{ icon: "󰐊", label: "Run…", run: () => win.askRun(p, it) }] : [],
            [{ sep: true },
             { icon: "󰆐", label: "Cut", run: () => app.ops.clip([p], true) },
             { icon: "󰆏", label: "Copy", run: () => app.ops.clip([p], false) }],
            it.dir ? [{ icon: "󰆒", label: "Paste into this folder", run: () => win.paste(p) }] : [],
            [{ icon: "󰑕", label: "Rename…", run: () => win.renameCurrent() },
             { icon: "󰪹", label: "Copy to…", run: () => win.copyTo([p], "copy") },
             { icon: "󰪹", label: "Move to…", run: () => win.copyTo([p], "move") },
             { icon: FmIcons.g.link, label: "Make link", run: () => win.makeLinks() },
             { icon: "\u{F04CE}", label: app.isStarred(p) ? "Unstar" : "Star", run: () => app.setStarred([p], !app.isStarred(p)) }],
            win.isArchive(it) ? [{ icon: "\u{F05C4}", label: "Extract here", run: () => app.ops.extract(p, FmPath.parent(p), res => win.selectIn(FmPath.parent(p), res.path)) },
                                 { icon: "\u{F05C4}", label: "Extract to…", run: () => picker.start({ title: "Extract “" + FmFormat.shown(it.name) + "” to…",
                                       action: "Extract here", path: FmPath.parent(p), run: d => app.ops.extract(p, d, res => win.selectIn(d, res.path)) }) }]
                               : [{ icon: "\u{F05C4}", label: "Compress…", run: () => win.compress([p]) }],
            win.isImage(it) ? [{ icon: "\u{F05EE}", label: "Mount the disk image", run: () => win.mountImage(p) }] : [],
            it.type.startsWith("image/") ? [{ icon: "\u{F024F}", label: "Set as wallpaper", run: () => win.setWallpaper(p) }] : [],
            app.scripts.length ? [{ icon: "\u{F018D}", label: "Scripts…", run: () => win.scriptsMenu([p], item, x, y) }] : [],
            [{ icon: FmIcons.g.trash, label: "Move to the trash", run: () => win.trashSel() },
             { icon: FmIcons.g.alert, label: "Delete for good…", danger: true, run: () => win.deleteSel() },
             { sep: true },
             { icon: "󰆏", label: "Copy path", run: () => win.copy(p) },
             { icon: "󰆏", label: "Copy name", run: () => win.copy(it.name) },
             { sep: true },
             { icon: "󰋽", label: "Properties", run: () => win.properties() }]))
    }

    // a menu closed: back to the files — unless what it did took the focus (a dialog's field)
    function refocus() {
        menuClosedAt = Date.now()
        Qt.callLater(() => {
            const f = bg.Window.activeFocusItem
            // a dialog a menu entry opened is still fading in (Modal: visible once opacity > 0): its field keeps the focus
            let opening = false
            for (let x = f; x && !opening; x = x.parent) opening = x.shown === true
            if (!f || f === keys || (!f.visible && !opening)) keys.forceActiveFocus()
        })
    }

    // a folder into the sidebar's bookmarks (GTK's list: file dialogs show it too)
    function bookmark(p) {
        if (!p.startsWith("/")) return
        backend.request("bookmark", { action: "add", path: p }, { done: () => win.toast("Added to the bookmarks", "info"), error: msg => win.toast(msg) })
    }
    function showProps(paths) { props.start(paths) }

    // ── Bookmark groups ──
    // the theme's hue roles (they follow light / dark and the theme); kept by role name
    readonly property var groupColors: [["red", "Red"], ["orange", "Orange"], ["yellow", "Yellow"], ["green", "Green"], ["teal", "Teal"],
                                        ["blue", "Blue"], ["chartPurple", "Purple"], ["accent", "Accent"]]
    // a bookmark into a group (or out of one), or into a new group
    function pinMenu(place, item, x, y) {
        subMenu.show(item, x, y, "Move to group", app.groups.map(g => ({ icon: g.id === place.group ? "󰄬" : "\u{F0256}", label: g.name,
                                                                         run: () => app.pinTo(place.uri, g.id) })).concat(
            place.group ? [{ icon: "\u{F0256}", label: "Out of the group", run: () => app.pinTo(place.uri, "") }] : [],
            [{ sep: true }, { icon: "\u{F0415}", label: "New group…", run: () => nameDialog.start({ title: "New bookmark group", icon: "\u{F0256}",
                 name: "Group", action: "Create", taken: n => app.groups.some(g => g.name === n),
                 run: (n, done) => { app.newGroup(n, place.uri); done("") } }) }]))
    }
    function groupMenu(g, item, x, y) {
        menu.show(item, x, y, g.name, [
            { icon: FmIcons.g.tab, label: "Open all in tabs", run: () => {
                for (const b of (app.places?.bookmarks ?? []).filter(b => app.groupPins[b.uri] === g.id && b.path)) win.newTab(b.path, { background: true }) } },
            { icon: g.open ? "\u{F0143}" : "\u{F0140}", label: g.open ? "Fold" : "Unfold", run: () => app.editGroup(g.id, { open: !g.open }) },
            { sep: true },
            { icon: "󰑕", label: "Rename…", run: () => nameDialog.start({ title: "Rename the group", icon: "\u{F0256}", name: g.name, action: "Rename",
                  taken: n => n !== g.name && app.groups.some(x => x.name === n), run: (n, done) => { app.editGroup(g.id, { name: n }); done("") } }) },
            { icon: "\u{F0E09}", label: "Colour…", run: () => subMenu.show(item, x, y, "Colour",
                  // each with a dot in its colour (the current one: a ring)
                  groupColors.map(c => ({ icon: g.color === c[0] ? "\u{F0766}" : "\u{F0765}", iconColor: Colors[c[0]], label: c[1] + (g.color === c[0] ? "  ✓" : ""),
                                          run: () => app.editGroup(g.id, { color: c[0] }) }))) },
            { sep: true },
            { icon: "󰅖", label: "Delete the group (bookmarks stay)", danger: true, run: () => app.deleteGroup(g.id) }])
    }

    // ── Servers, archives, extras ──
    // (answers the job: the address bar shows it running)
    // (the window can be gone when the server answers — closed, or a reload: the app, kept here,
    // still remembers it; only the folder isn't opened then)
    function connectTo(uri, keep) {
        const a = app
        return a.ops.connect(uri, res => {
            a.addHistory(uri)
            if (keep) a.rememberServer(uri)
            try { if (win.tab) win.tab.go(res.path) } catch (e) {}
        })
    }
    // a result (an archive, an extracted folder) selected where it is, if that's open here
    function selectIn(dir, path) { for (const t of tabs) if (t.path === dir) t.selectSoon([FmPath.base(path)]) }
    function isArchive(it) {
        return !it.dir && /\.(zip|jar|apk|tar|tgz|txz|tbz2|tzst|tar\.(gz|xz|bz2|zst)|7z|rar)$/i.test(it.name)
    }
    function isImage(it) { return !it.dir && /\.(iso|img)$/i.test(it.name) }
    function setWallpaper(p) {
        // through the shell (this process doesn't load Wallpapers); it checks the path itself
        Jobs.run(["qs", "ipc", "-p", Quickshell.shellDir, "call", "wallpapers", "apply", p], (code, out) => {
            const r = out.trim().split("\n").pop()
            if (code !== 0 || r !== "ok") win.toast(r || "The shell isn't running (it sets wallpapers)")
            else win.toast("Wallpaper set", "info")
        }, { LC_ALL: "C.UTF-8" })
    }
    function mountImage(p) {
        backend.request("mountImage", { path: p }, { done: res => { if (tab) tab.go(res.path) }, error: msg => win.toast(msg) })
    }
    // the scripts (custom actions) for these paths: a second menu
    function scriptsMenu(paths, item, x, y) {
        app.loadScripts(() => {
            const list = app.scripts.map(sc => ({ icon: "\u{F018D}", label: sc.name,
                run: () => backend.request("runScript", { script: sc.path, paths: paths, cwd: tab.path.startsWith("/") ? tab.path : home },
                                           { error: msg => win.toast(msg) }) }))
            subMenu.show(item, x, y, "Scripts", list.concat(list.length ? [{ sep: true }] : [],
                [{ icon: FmIcons.g.folderOpen, label: list.length ? "Open the scripts folder" : "No scripts yet — open the folder",
                   run: () => { Jobs.run(["mkdir", "-p", "--", app.scriptsDir], () => win.newTab(app.scriptsDir)) } }]))
        })
    }
    // the trash and the network have menus of their own
    function viewMenuFor(t, i, item, x, y) {
        if (t.special === "network") {
            if (i < 0) { menu.show(item, x, y, "Network", [{ icon: FmIcons.g.refresh, label: "Look again", run: () => t.folder.reload() },
                                                         { icon: "\u{F0415}", label: "Connect to server…", run: () => connectDialog.open() }]); return }
            const it = t.folder.at(i)
            menu.show(item, x, y, it.name, [{ icon: "\u{F0318}", label: "Connect", run: () => t.open(i) },
                                          { icon: "\u{F0415}", label: "Connect and keep in the sidebar", run: () => win.connectTo(it.uri, true) },
                                          { icon: "󰆏", label: "Copy address", run: () => win.copy(it.uri) },
                                          { icon: FmIcons.g.bookmark, label: "Add to bookmarks", run: () => backend.request("bookmark", { action: "add", uri: it.uri, label: it.name },
                                                { done: () => win.toast("Bookmarked — a click connects", "info"), error: msg => win.toast(msg) }) }])
            return
        }
        if (i < 0) {
            menu.show(item, x, y, "Trash", [{ icon: FmIcons.g.refresh, label: "Reload", run: () => t.folder.reload() },
                                           { icon: FmIcons.g.alert, label: "Empty the trash…", danger: true, run: () => win.emptyTrash() }])
            return
        }
        const it = t.folder.at(i)
        const sel = t.view.selection[it.key] ? t.view.selectedItems() : [it]
        menu.show(item, x, y, sel.length === 1 ? it.name : sel.length + " items", [
            { icon: "\u{F099B}", label: "Restore", run: () => win.restoreTrashed(sel) },
            { icon: FmIcons.g.alert, label: "Delete for good…", danger: true, run: () => win.deleteTrashed(sel) },
            { sep: true },
            { icon: "󰆏", label: "Copy original location", run: () => win.copy(sel.map(x => x.orig).join("\n")) }])
    }
    function restoreTrashed(items) {
        const t = tab
        app.ops.run("trashRestore", { items: trashEntries(items) }, "Restoring " + app.ops.names(items.map(x => x.orig)),
                       () => { if (t.special === "trash") t.folder.reload() })
    }
    function deleteTrashed(items) {
        const t = tab
        confirm.start({ icon: FmIcons.g.alert, tone: "danger", title: "Delete " + app.ops.names(items.map(x => x.orig)) + " for good?",
                        text: "This can't be undone.",
                        buttons: [{ label: "Delete", variant: "danger", run: () => app.ops.run("trashDelete", { items: trashEntries(items) },
                            "Deleting " + app.ops.names(items.map(x => x.orig)), () => { if (t.special === "trash") t.folder.reload() }) }] })
    }
    function emptyTrash() {
        const t = tab
        confirm.start({ icon: FmIcons.g.alert, tone: "danger", title: "Empty the trash?",
                        text: "Everything in it (also in the trash folders of mounted drives) is deleted for good.",
                        buttons: [{ label: "Empty", variant: "danger", run: () => app.ops.run("trashEmpty", {}, "Emptying the trash",
                            () => { for (const x of win.tabs) if (x.special === "trash") x.folder.reload() }) }] })
    }
    function compress(paths) {
        const t = tab
        if (!t || !writable(t)) return
        const base = paths.length === 1 ? FmPath.base(paths[0]).replace(/\.[^.]*$/, "") || FmPath.base(paths[0]) : "Archive"
        compressDialog.paths = paths
        compressDialog.start(base, t.folder.fs)
    }

    // the trash view's entries for the backend
    function trashEntries(items) { return items.map(it => ({ file: it.path, info: it.info, orig: it.orig })) }

    // ── Search, preview, properties ──
    // Enter in the search field: the first result opens (once the results are in)
    property bool openWhenFound: false
    function openFirstResult() {
        const t = tab
        if (!t) return
        keys.forceActiveFocus()
        if (t.folder.loading || t.folder.query === undefined) { openWhenFound = true; return }
        if (t.folder.count > 0) { t.view.first(false); t.activate(0) }
    }
    Connections {
        target: win.tab ? win.tab.folder : null
        function onLoaded() {
            if (!win.openWhenFound) return
            win.openWhenFound = false
            if (win.tab.folder.count > 0 && win.tab.folder.query !== undefined) { win.tab.view.first(false); win.tab.activate(0) }
        }
    }
    // a press in the files: the keys go to them (an empty search bar then closes itself)
    Connections {
        target: win.tab ? win.tab.view : null
        function onPressed() { if (!keys.activeFocus) keys.forceActiveFocus() }
    }
    function startSearch(text) {
        if (!tab) return
        tab.searching = true
        searchBar.start(text)
    }
    function endSearch() {
        if (tab) tab.endSearch()
        keys.forceActiveFocus()
    }
    // the files of the view in order (folders left out), from the current one
    function preview() {
        const t = tab
        if (!t || t.view.currentIndex < 0) return
        const cur = t.folder.at(t.view.currentIndex)
        const list = []
        let at = 0
        for (let i = 0; i < t.folder.count; i++) {
            const it = t.folder.at(i)
            if (it.dir) continue
            if (it === cur) at = list.length
            list.push({ name: it.name, size: it.size, type: it.type, path: t.folder.pathOf(it) })
        }
        if (cur.dir || list.length === 0) { t.open(t.view.currentIndex); return }
        viewer.open(list, at)
    }
    function properties() {
        const ps = selPaths()
        props.start(ps.length ? ps : (tab ? [tab.path] : []))
    }

    // ── Operations ──
    // the selection, or the item under the cursor when nothing is selected
    function selPaths() {
        const t = tab
        if (!t) return []
        let items = t.view.selectedItems()
        if (items.length === 0 && t.view.currentIndex >= 0) items = [t.folder.at(t.view.currentIndex)]
        return items.filter(x => !!x).map(x => t.folder.pathOf(x))
    }
    function writable(t) {
        // a view (Recent, Starred …): each file's own folder decides (the backend says so)
        if (t.special !== "" || t.folder.canWrite) return true
        toast("This folder is read-only")
        return false
    }
    function paste(dest) {
        if (tab && dest === tab.path && !writable(tab)) return
        app.ops.paste(dest)
    }
    function trashSel() {
        // in the trash view: Delete means for good (asks)
        if (tab?.special === "trash") { const v = tab.view; const sel = v.selectedItems(); if (sel.length) deleteTrashed(sel); return }
        const ps = selPaths()
        if (ps.length === 0 || !writable(tab)) return
        if (Settings.files.confirmTrash ?? false)
            confirm.start({ icon: FmIcons.g.trash, tone: "warning", title: "Move " + app.ops.names(ps) + " to the trash?",
                            text: "You can get them back from the trash (or with Ctrl+Z).",
                            buttons: [{ label: "Move to the trash", variant: "primary", run: () => app.ops.trash(ps) }] })
        else app.ops.trash(ps)
    }
    function deleteSel() {
        const ps = selPaths()
        if (ps.length === 0 || !writable(tab)) return
        confirm.start({ icon: FmIcons.g.alert, tone: "danger",
                        title: "Delete " + app.ops.names(ps) + " for good?",
                        text: "They won't go to the trash, and this can't be undone.",
                        buttons: [{ label: "Delete", variant: "danger", run: () => app.ops.remove(ps) }] })
    }
    function renameCurrent() {
        const t = tab
        const i = t ? t.view.currentIndex : -1
        const it = i >= 0 ? t.folder.at(i) : null
        if (!it || !writable(t)) return
        const old = t.folder.pathOf(it)
        nameDialog.start({ title: "Rename “" + FmFormat.shown(it.name) + "”", icon: "󰑕", name: it.name, action: "Rename",
                           stem: !it.dir, fs: t.folder.fs, taken: n => t.folder === t.dir && t.folder.indexOf(n) >= 0 && n !== it.name,
                           run: (name, done) => app.ops.rename(old, name, (res, err) => {
                               if (res && t.folder === t.dir) t.selectSoon([FmPath.base(res.path)])
                               done(err)
                           }) })
    }
    function newFolder() {
        const t = tab
        if (!t || !writable(t)) return
        let name = "New Folder", n = 2
        while (t.folder.indexOf(name) >= 0) name = "New Folder " + n++
        nameDialog.start({ title: "New folder", icon: FmIcons.g.newFolder, name: name, action: "Create", fs: t.folder.fs,
                           taken: x => t.folder.indexOf(x) >= 0,
                           run: (nm, done) => app.ops.mkdir(t.path, nm, (res, err) => {
                               if (res) t.selectSoon([nm])
                               done(err)
                           }) })
    }
    // "New document": an empty file, or one from ~/Templates
    function documentMenu(item, x, y) {
        backend.request("templates", {}, {
            done: res => {
                const tpl = (res.items ?? []).map(it => ({ icon: FmIcons.item({ type: "" }),
                    label: (it.group ? it.group + " › " : "") + FmFormat.shown(it.name), run: () => win.newDocument(it.name, it.path) }))
                subMenu.show(item, x, y, "New document", [{ icon: FmIcons.g.file, label: "Empty file", run: () => win.newDocument("New File", "") }]
                    .concat(tpl.length ? [{ sep: true }].concat(tpl) : []))
            },
            error: () => win.newDocument("New File", "")
        })
    }
    function newDocument(name, template) {
        const t = tab
        if (!t || !writable(t)) return
        nameDialog.start({ title: template ? "New document from “" + FmFormat.shown(name) + "”" : "New empty file", icon: FmIcons.g.file,
                           name: name, action: "Create", stem: true, fs: t.folder.fs, taken: x => t.folder.indexOf(x) >= 0,
                           run: (nm, done) => app.ops.newfile(t.path, nm, template, (res, err) => {
                               if (res) t.selectSoon([nm])
                               done(err)
                           }) })
    }
    function makeLinks() {
        const ps = selPaths()
        if (ps.length && writable(tab)) app.ops.copy(ps, tab.path, "link")
    }
    function copyTo(paths, mode) {
        picker.start({ title: (mode === "move" ? "Move " : "Copy ") + app.ops.names(paths) + " to…",
                       action: mode === "move" ? "Move here" : "Copy here", path: tab ? tab.path : home,
                       run: dest => app.ops.copy(paths, dest, mode) })
    }

    // something dropped on a folder (the view, a folder row, a tab, a sidebar place)
    function handleDrop(drop, dest) {
        const urls = drop.hasUrls ? drop.urls.map(u => String(u)) : []
        const paths = urls.map(u => FmPath.fromArg(u)).filter(p => p !== "")
        if (paths.length && dest === "trash:") {
            drop.accept(Qt.MoveAction)
            app.ops.trash(paths)
            return
        }
        if (paths.length) {
            // ours: the keys decide (as far as the compositor passes them on), else move on the
            // same drive / copy across; from another app: a copy (a link with Ctrl+Shift)
            const ours = app.dragging.length > 0
            const mode = drop.proposedAction === Qt.LinkAction ? "link"
                       : !ours ? "copy"
                       : drop.proposedAction === Qt.CopyAction ? "copy" : "auto"
            drop.accept(mode === "link" ? Qt.LinkAction : mode === "copy" ? Qt.CopyAction : Qt.MoveAction)
            if (mode !== "copy" && paths.every(p => FmPath.parent(p) === dest)) return       // already there
            app.ops.copy(paths, dest, mode)
            return
        }
        // a browser's image, link or text: saved as a new file
        const img = FmDrop.imageType(drop.formats)
        const link = urls.find(u => /^https?:\/\//i.test(u))
        if (img !== "") {
            const buf = drop.getDataAsArrayBuffer(img)
            if (buf && buf.byteLength > 0) {
                save(dest, "Saved from web." + FmDrop.ext(img), { base64: FmDrop.b64(new Uint8Array(buf)) })
                drop.accept(Qt.CopyAction)
                return
            }
        }
        if (link) {
            const l = FmDrop.webLink(link, drop.hasText && drop.text !== link ? drop.text : "")
            save(dest, l.name, { text: l.text })
        } else if (drop.hasText && drop.text !== "") {
            save(dest, "Dropped text.txt", { text: drop.text })
        } else {
            return
        }
        drop.accept(Qt.CopyAction)
    }
    function save(dest, name, data) {
        backend.request("save", Object.assign({ dir: dest, name: name }, data), {
            done: res => { for (const t of tabs) if (t.path === dest) t.selectSoon([FmPath.base(res.path)]) },
            error: msg => win.toast(msg)
        })
    }

    // opening a file: programs, scripts and launchers ask first; the rest goes to its app
    function openFile(p, it) {
        if (it.type === "application/x-desktop" || p.endsWith(".desktop")) { openLauncher(p, it); return }
        // an AppImage is a program: it runs; a downloaded one isn't executable yet (asks once to allow it)
        if (/appimage/i.test(it.type) || /\.appimage$/i.test(p)) {
            if (it.exec) backend.request("run", { path: p }, { error: msg => win.toast(msg) })
            else askRun(p, it)
            return
        }
        if (it.exec && (it.type.startsWith("text/") || /shellscript|x-executable|pie-executable|x-sharedlib|x-perl|x-python|x-ruby/.test(it.type))) {
            // Settings.files.executables: ask (default) · open (as text) · run
            const how = Settings.files.executables ?? "open"
            if (how === "run") { backend.request("run", { path: p }, { error: msg => win.toast(msg) }); return }
            if (how === "ask" || !(it.type.startsWith("text/") || /script|x-perl|x-python|x-ruby/.test(it.type))) { askRun(p, it); return }
        }
        backend.request("launch", { path: p }, { done: res => { win.noteRecent(p, it.type); Compositor.focusLaunched(res.app) }, error: msg => win.toast(msg) })
    }
    // what's opened here goes to Recent (GTK's list: other apps see it too)
    function noteRecent(p, type) { backend.request("addRecent", { path: p, type: type ?? "" }, { error: () => {} }) }
    function askRun(p, it) {
        const script = it.type.startsWith("text/") || /script|x-perl|x-python|x-ruby/.test(it.type)
        if (!it.exec) {
            // not executable (a download): allowed first, then run
            confirm.start({ icon: "󰐊", tone: "warning", title: "Run “" + FmFormat.shown(FmPath.base(p)) + "”?",
                            text: "It's a program that isn't allowed to run yet (a download?). Running it can do anything you can do — only run what you trust.",
                            buttons: [{ label: "Allow and run", variant: "primary", run: () => win.allowAndRun(p) }] })
            return
        }
        confirm.start({ icon: "󰐊", tone: "warning",
                        title: "Run “" + FmFormat.shown(FmPath.base(p)) + "”?",
                        text: (script ? "It's an executable script." : "It's a program.")
                              + " Running it can do anything you can do — only run what you trust.",
                        buttons: [].concat(
                            script ? [{ label: "Open as text", run: () => backend.request("launch", { path: p }, { done: res => Compositor.focusLaunched(res.app), error: msg => win.toast(msg) }) }] : [],
                            [{ label: "Run in terminal", run: () => backend.request("run", { path: p, terminal: true }, { error: msg => win.toast(msg) }) },
                             { label: "Run", variant: "primary", run: () => backend.request("run", { path: p }, { error: msg => win.toast(msg) }) }]) })
    }
    function isScript(it) { return it.type.startsWith("text/") && it.exec || /shellscript|x-perl|x-python|x-ruby|x-php|javascript/.test(it.type) }
    // kitty --hold: what it printed stays readable after it ends; a script not executable yet is made so first
    function runInTerminal(p, it) {
        const run = () => backend.request("run", { path: p, terminal: true }, { error: msg => win.toast(msg) })
        if (it.exec) { run(); return }
        backend.request("props", { path: p }, {
            done: pr => backend.request("chmod", { path: p, mode: pr.lmode | ((pr.lmode & 0o444) >> 2) }, { done: run, error: msg => win.toast(msg) }),
            error: msg => win.toast(msg) })
    }
    function allowAndRun(p) {
        backend.request("props", { path: p }, {
            done: pr => backend.request("chmod", { path: p, mode: pr.lmode | ((pr.lmode & 0o444) >> 2) }, {
                done: () => backend.request("run", { path: p }, { error: msg => win.toast(msg) }),
                error: msg => win.toast(msg) }),
            error: msg => win.toast(msg) })
    }
    function openLauncher(p, it) {
        backend.request("desktop", { path: p }, {
            done: d => {
                const editor = () => backend.request("launch", { path: p }, { error: msg => win.toast(msg) })
                // a saved web link: just the link, in the browser
                if (d.type === "Link" && /^(https?|mailto):/i.test(d.url)) {
                    backend.request("openUri", { uri: d.url }, { error: msg => win.toast(msg) })
                    return
                }
                if (d.trusted) { backend.request("launchDesktop", { path: p }, { error: msg => win.toast(msg) }); return }
                confirm.start({ icon: FmIcons.g.alert, tone: "warning",
                                title: "Untrusted app launcher “" + FmFormat.shown(d.name || FmPath.base(p)) + "”",
                                text: "A launcher runs a command. Only trust it if you know where it came from. It runs:",
                                detail: d.type === "Link" ? d.url : d.exec,
                                buttons: [{ label: "Open as text", run: editor },
                                          { label: "Trust and launch", variant: "danger", run: () => backend.request("trust", { path: p }, {
                                              done: () => backend.request("launchDesktop", { path: p }, { error: msg => win.toast(msg) }),
                                              error: msg => win.toast(msg) }) }] })
            },
            error: msg => win.toast(msg)
        })
    }

    // kitty in that folder (argv: the path is one argument, never parsed)
    function terminal(p) {
        Jobs.which(["kitty"], have => {
            if (!have.kitty) { win.toast("kitty isn't installed (" + Jobs.installHint("kitty") + ")"); return }
            Jobs.detached(["kitty", "--directory", p])
        })
    }
    // ncdu on a folder, in kitty (local folders only: over the network it reads every file's
    // size through the server); the path is one argument, after "--"
    function diskUsage(p) {
        Jobs.which(["kitty", "ncdu"], have => {
            if (!have.kitty) { win.toast("kitty isn't installed (" + Jobs.installHint("kitty") + ")"); return }
            if (!have.ncdu) { win.toast("ncdu isn't installed (" + Jobs.installHint("ncdu") + ")"); return }
            Jobs.detached(["kitty", "--directory", p, "--title", "Disk usage — " + FmPath.base(p), "ncdu", "-x", "--", p])
            Compositor.focusLaunched(["kitty"])
        })
    }
    function copy(text) {
        Jobs.run(["wl-copy", "--", text], code => { if (code !== 0) win.toast("Couldn't copy (" + Jobs.installHint("wl-copy") + "?)") })
    }
}
