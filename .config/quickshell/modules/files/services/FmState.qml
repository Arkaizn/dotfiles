import Quickshell
import Quickshell.Io
import QtQuick

// The file manager's own state (what it remembers, not preferences):
// ~/.local/state/quickshell/files/state.json, owned by the files process
// (the backend creates the folder, 0700). Written a second after a change and
// never only on exit: update.sh and crashes end the process without warning.
//
// Format (version 2; unknown keys are kept, bad values read as their default):
//   view       "list" | "grid"              the default view (folders without their own)
//   sort       { by: "name" | "size" | "mtime" | "type", reverse, dirsFirst }   the default order
//   iconSize   { list: px, grid: px }       the default icon sizes (FmZoom's steps)
//   folders    { "<path>": { view?, sort?, iconSize?: { list?, grid? }, t } }
//                                           folders with their own view (FmViews; at most 500, t = last change, ms)
//   hidden     show hidden files (every window)
//   columns    ["size", "mtime", "type", "perms"]   the list's columns besides the name, in order (FmColumns)
//   window     { width, height }            the last window's size (new windows get it)
//   windows    [{ tabs: [{ path }], active, width, height }]   open windows: reopened after a restart
//              (a tab's path may be a view: "recent:", "starred:", "trash:", "network:")
//   starred    ["<path>", …]                starred files and folders (the Starred view)
//   servers    [{ uri, name }]              saved server addresses (sidebar → Network)
//   serverHistory ["sftp://me@host", …]      addresses connected to, newest first (never a password)
//   sideOrder  ["recent", "home", …]         the sidebar's top part, in order (dragged there)
//   groups     [{ id, name, color, open }]   bookmark groups (color: a Colors role name: red, blue, …)
//   groupPins  { "<bookmark uri>": group id } which bookmark is in which group (GTK's file keeps the bookmarks)
//              (version 1 had [{ path }]: read as one tab each)
//
//   get(key, def) · set(key, value) · flush()
Scope {
    id: root

    readonly property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                   + "/quickshell/files/state.json"
    property var data: ({})

    function get(key, def) {
        const v = data[key]
        return v === undefined || v === null ? def : v
    }
    function set(key, value) {
        if (JSON.stringify(data[key]) === JSON.stringify(value)) return
        const o = Object.assign({}, data)
        o[key] = value
        data = o
        saveTimer.restart()
    }
    // now instead of in a moment (the window closing)
    function flush() {
        if (!saveTimer.running) return
        saveTimer.stop()
        _write()
    }
    function _write() { file.setText(JSON.stringify(Object.assign({}, data, { version: 2 }), null, 2) + "\n") }

    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        data = o !== null && typeof o === "object" && !Array.isArray(o) ? o : {}
    }

    Timer { id: saveTimer; interval: 1000; onTriggered: root._write() }

    // read now, synchronously: FilesApp reopens the last window from it right after
    Component.onCompleted: parse(file.text() ?? "")

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
}
