import Quickshell
import QtQuick
import qs.services
import "lib/FmPath.js" as FmPath
import "lib/FmFormat.js" as FmFormat

// The file manager's operations, shared by every window: the jobs running in
// the backend (progress, pause, cancel), the questions they ask (conflicts,
// errors — the window used last shows them), undo / redo, the clipboard.
//
//   run(op, args, label, then) · mount(volume, name, then) · unmount(uri, name, eject) · connect(uri, then)
//   extract(path, dest, then) · compress(paths, dest, name, format, password, then)
//   copy(sources, dest, mode)   mode: copy | move | link | auto (a move on the same drive)       trash(paths) · remove(paths) (for good)
//   rename(path, name, cb) · mkdir(dir, name, cb) · newfile(dir, name, template, cb)
//   undo() · redo() · canUndo / canRedo · undoLabel / redoLabel
//   clip(paths, cut) · paste(dest) · cut: { path: true } (shown faded until pasted)
//   jobs: [{ id, label, done, total, bytes, totalBytes, current, paused, state, error }]
//         state: running | done | failed | cancelled
//   pause(id, on) · cancel(id) · forget(id)
//   question: the first open ask { job, kind, src, dst, suggest, folders, path, error } · answer(action, all, name)
//   signal finished(job, res)   an operation ended (the window selects what it made, shows "Undo")
//   signal notice(text, undoable)   something to say in the window's toast
Scope {
    id: root

    required property var backend

    property var jobs: []
    property var asks: []                     // open questions, oldest first
    readonly property var question: asks.length ? asks[0] : null
    property var undoStack: []                // [{ label, undo: () => …, redo: () => … }]
    property var redoStack: []
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property string undoLabel: canUndo ? undoStack[undoStack.length - 1].label : ""
    readonly property string redoLabel: canRedo ? redoStack[redoStack.length - 1].label : ""
    readonly property bool busy: jobs.some(j => j.state === "running")
    property var cut: ({})
    signal finished(var job, var res)
    signal notice(string text, bool undoable)

    function names(paths) {
        return paths.length === 1 ? "“" + FmFormat.shown(FmPath.base(paths[0])) + "”" : paths.length + " items"
    }
    function where(dir) { return dir === Quickshell.env("HOME") ? "Home" : "“" + FmFormat.shown(FmPath.base(dir)) + "”" }

    // ── Jobs ──
    function _update(id, patch) { jobs = jobs.map(j => j.id === id ? Object.assign({}, j, patch) : j) }
    function job(id) { return jobs.find(j => j.id === id) ?? null }

    // a long operation; on success `then(res)` (undo bookkeeping), every answer to the asks
    function _start(op, args, label, then, extra) {
        let id = 0
        id = backend.request(op, args, {
            progress: m => root._update(id, { done: m.done, total: m.total, bytes: m.bytes, totalBytes: m.totalBytes,
                                              current: m.current, paused: m.paused === true }),
            ask: m => root.asks = root.asks.concat([Object.assign({ job: id, label: label }, m)]),
            done: res => {
                root.asks = root.asks.filter(a => a.job !== id)
                root._update(id, { state: res.cancelled ? "cancelled" : "done", doneAt: Date.now() })
                if (then) then(res)
                root.finished(root.job(id), res)
                root._notifyEnd(id, label, res)
            },
            error: (msg, code) => {
                root.asks = root.asks.filter(a => a.job !== id)
                root._update(id, { state: code === "cancelled" ? "cancelled" : "failed", error: msg, doneAt: Date.now() })
                if (code !== "cancelled") root.notice(label + ": " + msg, false)
            }
        })
        jobs = jobs.filter(j => j.state === "running" || Date.now() - (j.doneAt ?? 0) < 60000)
                   .concat([Object.assign({ id: id, op: op, label: label, done: 0, total: 0, bytes: 0, totalBytes: 0, current: "",
                              paused: false, state: "running", error: "", started: Date.now(), dest: args.dest ?? "" }, extra ?? {})])
        return id
    }
    // any long backend op shown with its progress and questions (the trash view's restore / delete …)
    function run(op, args, label, then) { return _start(op, args, label, then) }
    function pause(id, on) { backend.request("pause", { target: id, paused: on }); _update(id, { paused: on }) }
    function cancel(id) { backend.cancel(id); asks = asks.filter(a => a.job !== id) }
    function forget(id) { jobs = jobs.filter(j => j.id !== id) }
    // extra: a password answer's { user, domain, password, anonymous, remember } or { choice }
    function answer(action, all, name, extra) {
        const q = question
        if (!q) return
        asks = asks.slice(1)
        const a = Object.assign({ target: q.job, action: action, all: all === true }, extra ?? {})
        if (name) a.name = name
        backend.request("answer", a)
        // "for all": the other open questions of that job that this answer covers go too
        if (all) asks = asks.filter(x => !(x.job === q.job && x.kind === q.kind))
    }

    // a long one ended while no window has the focus: say it the shell's way
    property bool anyFocused: false
    function _notifyEnd(id, label, res) {
        const j = job(id)
        if (!j || anyFocused || Date.now() - j.started < 5000) return
        Jobs.run(["notify-send", "--app-name=Files", "--icon=system-file-manager",
                  res.cancelled ? "Stopped" : "Done", label])
    }

    // ── Operations (each with its undo) ──
    function copy(sources, dest, mode) {
        if (sources.length === 0) return
        const verb = mode === "move" ? "Moving" : mode === "link" ? "Linking" : mode === "auto" ? "Moving / copying" : "Copying"
        const label = verb + " " + names(sources) + " to " + where(dest)
        const rec = !_replaying
        _start("copy", { sources: sources, dest: dest, mode: mode }, label, res => {
            const made = res.made ?? []
            if (made.length === 0 || !rec) return
            const m = res.mode ?? mode           // "auto" came back as what it was
            const done = (m === "move" ? "Moved " : m === "link" ? "Linked " : "Copied ") + names(made.map(x => x.src))
            if (m === "move") {
                _push(done, () => root._relocate(made.map(x => ({ from: x.dst, to: x.src })), "Moving back " + names(made.map(x => x.dst))),
                            () => root.copy(made.map(x => x.src), dest, "move"))
            } else {
                // undo of a copy / link: the new ones go to the trash (never deleted for good)
                _push(done, () => root.trash(made.map(x => x.dst), true),
                            () => root.copy(made.map(x => x.src), dest, m))
            }
            root.notice(done, true)
        })
    }
    function _relocate(pairs, label) {
        _start("relocate", { pairs: pairs }, label, null)
    }
    function trash(paths, fromUndo) {
        if (paths.length === 0) return
        const rec = !_replaying && !fromUndo
        _start("trash", { paths: paths }, "Moving " + names(paths) + " to the trash", res => {
            const t = res.trashed ?? []
            if (t.length === 0 || !rec) return
            const what = "Moved " + names(t) + " to the trash"
            _push(what, () => root.restore(t), () => root.trash(t, true))
            root.notice(what, true)
        })
    }
    function restore(paths) {
        _start("restore", { paths: paths }, "Restoring " + names(paths), res => {
            if ((res.missing ?? []).length) root.notice(names(res.missing) + " isn't in the trash any more", false)
        })
    }
    // for good: no undo (the window asked first)
    function remove(paths) {
        if (paths.length === 0) return
        _start("delete", { paths: paths }, "Deleting " + names(paths), res => root.notice("Deleted " + names(res.deleted ?? []), false))
    }
    function rename(path, name, cb) {
        const rec = !_replaying
        backend.request("rename", { path: path, name: name }, {
            done: res => {
                const old = FmPath.base(path)
                if (rec) _push("Renamed “" + FmFormat.shown(old) + "”", () => root.rename(res.path, old), () => root.rename(path, name))
                if (cb) cb(res, "")
            },
            error: msg => { if (cb) cb(null, msg); else root.notice(msg, false) }
        })
    }
    function mkdir(dir, name, cb) {
        const rec = !_replaying
        backend.request("mkdir", { dir: dir, name: name }, {
            done: res => { if (rec) _push("New folder “" + FmFormat.shown(name) + "”", () => root.trash([res.path], true), () => root.mkdir(dir, name)); if (cb) cb(res, "") },
            error: msg => { if (cb) cb(null, msg); else root.notice(msg, false) }
        })
    }
    function newfile(dir, name, template, cb) {
        const rec = !_replaying
        backend.request("newfile", { dir: dir, name: name, template: template || "" }, {
            done: res => { if (rec) _push("New document “" + FmFormat.shown(name) + "”", () => root.trash([res.path], true), () => root.newfile(dir, name, template)); if (cb) cb(res, "") },
            error: msg => { if (cb) cb(null, msg); else root.notice(msg, false) }
        })
    }

    // ── Drives, servers, archives (they may ask for a password: PasswordDialog) ──
    function mount(volume, name, then) { _start("mount", { volume: volume }, "Opening " + name, then) }
    function unmount(uri, name, eject) { _start("unmount", { uri: uri, eject: eject === true }, (eject ? "Ejecting " : "Unmounting ") + name, null) }
    function connect(uri, then) { _start("connect", { uri: uri }, "Connecting to " + uri.replace(/^[a-z]+:\/\//, ""), then) }
    function extract(path, dest, then) {
        _start("extract", { path: path, dest: dest }, "Extracting " + names([path]), res => { if (then) then(res) }, { dest: dest })
    }
    function compress(paths, dest, name, format, password, then) {
        const args = { paths: paths, dest: dest, name: name, format: format }
        if (password) args.password = password
        _start("compress", args, "Compressing " + names(paths), res => { if (then) then(res) }, { dest: dest })
    }

    // ── Undo / redo ──
    // set while undo / redo start their operations: those make no undo entries (each
    // operation reads it when it starts — its result comes later)
    property bool _replaying: false
    function _push(label, undo, redo) {
        undoStack = undoStack.concat([{ label: label, undo: undo, redo: redo }]).slice(-50)
        redoStack = []
    }
    function undo() {
        if (!canUndo) return
        const e = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        redoStack = redoStack.concat([e])
        _replay(e.undo)
        notice("Undone: " + e.label, false)
    }
    function redo() {
        if (!canRedo) return
        const e = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, -1)
        undoStack = undoStack.concat([e])
        _replay(e.redo)
    }
    function _replay(f) { _replaying = true; try { f() } finally { _replaying = false } }

    // ── Clipboard (other file managers read it too) ──
    function clip(paths, isCut) {
        if (paths.length === 0) return
        backend.request("clipSet", { paths: paths, cut: isCut }, {
            done: () => {
                const c = {}
                if (isCut) for (const p of paths) c[p] = true
                root.cut = c
                root.notice((isCut ? "Cut " : "Copied ") + names(paths) + " — paste with Ctrl+V", false)
            },
            error: msg => root.notice("Couldn't use the clipboard: " + msg, false)
        })
    }
    function paste(dest) {
        backend.request("clipGet", {}, {
            done: res => {
                const paths = res.paths ?? []
                if (paths.length === 0) { root.notice("There are no files on the clipboard", false); return }
                root.copy(paths, dest, res.cut ? "move" : "copy")
                // a cut is used up once pasted (like Nautilus)
                if (res.cut) root.cut = ({})
            },
            error: msg => root.notice(msg, false)
        })
    }
}
