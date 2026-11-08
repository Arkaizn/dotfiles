pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib

// Connection to the mediasync bridge (~/git/mediasync, docs/API.md): local
// MPRIS players and remote Jellyfin sessions through one socket API.
// MEDIASYNC.md explains setup, MEDIASYNC_PLAN.md the decisions (D1–D8).
//
//   state         "off" (Settings → Media) | "connecting" | "connected"
//                 | "reconnecting" (lost it, last state kept) | "unavailable"
//   connected     the views use the bridge: subscribed, or reconnecting with
//                 the last snapshot still shown (`live` = really subscribed)
//   sessions      bridge sessions in its presentation order (hidden ones left out)
//   selectedId    the bridge's selected session ("" = none) + selectionReason
//   settings      settings.get: { settings: { mode, … }, local_enabled, remote_enabled }
//   providers, servers, diagnostics, info (hello)
//   problem       why it's not connected, for the UI
//   command(sessionId, name, args, cb)   only ever to that session (never a default)
//   request(method, params, cb)          cb(err, result); err = { code, message }
//
// One Socket, `subscribe` on every (re)connect (the snapshot replaces all
// state, no event history needed), reconnect backoff 1 s → 30 s, pending
// requests fail on disconnect or after their timeout.
// mediasyncd restarts itself after every package update (the socket is gone
// for a few seconds): a lost connection first goes "reconnecting" for up to
// `graceMs`, keeps the last sessions on screen and retries every 500 ms,
// without any error in the UI. Only when that runs out is everything cleared
// (no stale remote sessions shown for longer, D6) and it's "unavailable".
//   queueUpdated(sessionId)   the bridge's queue.changed event
//   resubscribed()            a new snapshot replaced everything (after a reconnect too)
Singleton {
    id: root

    readonly property bool wanted: Settings.loaded && (Settings.media.bridge ?? true)
    readonly property string socketPath: Quickshell.env("MEDIASYNC_SOCKET")
        || (Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/mediasync/mediasync.sock" : "")

    property string state: "off"
    readonly property bool connected: state === "connected" || state === "reconnecting"
    readonly property bool live: state === "connected"
    readonly property int graceMs: 30000
    signal queueUpdated(string sessionId)
    signal resubscribed()
    property string problem: ""
    property var info: null
    property var sessions: []
    readonly property var byId: { const m = {}; for (const s of root.sessions) m[s.id] = s; return m }
    property string selectedId: ""
    property string selectionReason: ""
    property var settings: null
    property var providers: []
    property var servers: []
    property var diagnostics: null
    property int revision: 0
    property var busy: ({})                 // session id → true while a command runs
    property var lastError: null            // { sessionId, text, at } of the last failed command
    // install / service check while unavailable: "" | "missing" | "installed"; systemctl is-active
    property string installState: ""
    property string serviceState: ""

    function hasMethod(m) { return (root.info?.methods ?? []).includes(m) }
    function session(id) { return root.byId[id] ?? null }

    // ── Requests ─────────────────────────────────────────────────────────────
    property int _seq: 0
    property var _pending: ({})             // id → { cb, due } (not a binding source)

    function request(method, params, cb, timeoutMs) {
        if (!socket.connected) { if (cb) cb({ code: "disconnected", message: "" }, null); return }
        const id = ++root._seq
        root._pending[id] = { cb: cb ?? null, due: Date.now() + (timeoutMs ?? 10000) }
        // params can hold a password (jellyfin.login): never log this line
        socket.write(JSON.stringify({ jsonrpc: "2.0", id: id, method: method, params: params ?? {} }) + "\n")
        socket.flush()
        sweep.start()
    }

    function _settle(id, err, result) {
        const p = root._pending[id]
        if (!p) return                      // timed out already, or from a closed connection
        delete root._pending[id]
        if (p.cb) {
            try { p.cb(err, result) } catch (e) { console.warn("mediasync: callback failed:", e) }
        }
    }

    function _failAll(code) {
        const ids = Object.keys(root._pending)
        for (const id of ids) root._settle(id, { code: code, message: "" }, null)
    }

    Timer {
        id: sweep
        interval: 1000
        repeat: true
        onTriggered: {
            const now = Date.now()
            for (const id of Object.keys(root._pending))
                if (root._pending[id].due < now) root._settle(id, { code: "request_timeout", message: "" }, null)
            if (Object.keys(root._pending).length === 0) stop()
        }
    }

    // ── Commands and settings ────────────────────────────────────────────────
    // name: play | pause | play_pause | stop | next | previous | seek | set_volume
    // args: { position_ms } / { offset_ms } / { volume }
    function command(sessionId, name, args, cb) {
        if (!sessionId) { if (cb) cb({ code: "no_session_selected", message: "" }, null); return }
        root._setBusy(sessionId, true)
        root.request("player.command", Object.assign({ session_id: sessionId, command: name }, args ?? {}), (err, res) => {
            root._setBusy(sessionId, false)
            // lost the connection meanwhile (service restart): quiet, it reconnects by itself
            if (err && err.code === "disconnected") console.info("mediasync:", name, "not sent: reconnecting")
            else if (err) {
                root.reportError(sessionId, err)
                // the message says why (e.g. Jellyfin's HTTP status); the bridge never puts secrets in it
                console.warn("mediasync:", name, "failed:", err.code, err.message)
            }
            if (cb) cb(err, res)
        }, 15000)       // the bridge's own limits: 5 s to accept + up to 5 s to verify a remote effect
    }
    // shown under the controls for a few seconds (dashboard)
    function reportError(sessionId, err) {
        root.lastError = { sessionId: sessionId, text: MediaSources.errorText(err), at: Date.now() }
    }
    function _setBusy(id, on) {
        const b = Object.assign({}, root.busy)
        if (on) b[id] = true; else delete b[id]
        root.busy = b
    }

    // id "" = back to automatic selection
    function select(id, cb) {
        root.request("sessions.select", { session_id: id || null }, (err, res) => {
            if (!err) { root._bridgeSelected = res.session?.id ?? ""; root._bridgeReason = res.reason ?? ""; root._applySelection() }
            if (cb) cb(err, res)
        })
    }

    // any of mode, preferred_player, prefer_origin, show_view_only, show_stale,
    // dedup, local_enabled, remote_enabled, or { reset: true }
    function updateSettings(changes, cb) {
        root.request("settings.update", changes, (err, res) => {
            if (!err) root.settings = res
            if (cb) cb(err, res)
        })
    }

    function refreshSettings() { root.request("settings.get", {}, (err, res) => { if (!err) root.settings = res }) }
    function refreshProviders() {
        root.request("providers.status", {}, (err, res) => { if (!err) root.providers = res.providers ?? [] })
        root.request("jellyfin.servers", {}, (err, res) => { if (!err) root.servers = res.servers ?? [] })
    }
    function refreshDiagnostics(cb) {
        root.request("diagnostics.get", {}, (err, res) => { if (!err) root.diagnostics = res; if (cb) cb(err, res) })
    }
    // every session incl. hidden ones (duplicates, view-only, excluded by mode), for the settings page
    function listAll(cb) { root.request("sessions.list", { include_hidden: true }, cb) }

    // the password is only put into this one request; nothing keeps it
    function login(server, user, password, cb) {
        root.request("jellyfin.login", { server: server, username: user, password: password }, (err, res) => {
            root.refreshProviders()
            if (cb) cb(err, res)
        }, 30000)
    }
    function logout(server, cb) {
        root.request("jellyfin.logout", { server: server }, (err, res) => { root.refreshProviders(); if (cb) cb(err, res) }, 30000)
    }
    function reloadConfig(cb) {
        root.request("service.reload", {}, (err, res) => { root.refreshProviders(); root.refreshSettings(); if (cb) cb(err, res) })
    }

    // ── Server management (bridge API added later: used only when `hello` lists it) ──
    function addServer(def, cb) { root.request("jellyfin.servers.add", def, (err, res) => { root.refreshProviders(); if (cb) cb(err, res) }, 30000) }
    function updateServer(def, cb) { root.request("jellyfin.servers.update", def, (err, res) => { root.refreshProviders(); if (cb) cb(err, res) }, 30000) }
    function removeServer(name, cb) { root.request("jellyfin.servers.remove", { name: name }, (err, res) => { root.refreshProviders(); if (cb) cb(err, res) }, 30000) }
    function testServer(url, cb) { root.request("jellyfin.test", { url: url }, cb, 30000) }

    // ── Snapshot and events ──────────────────────────────────────────────────
    // A session the bridge removes stays for `leaveGraceMs` (with the selection
    // on it): Jellyfin clients such as Finamp drop out of the server's list for
    // a moment during remote commands (a queue jump) and come back with the same
    // id. Without this the card emptied and its sheet closed for that second.
    // A full subscribe (reconnect) still replaces everything at once.
    readonly property int leaveGraceMs: 4000
    property var _leaving: ({})             // id → { session, since }
    property string _bridgeSelected: ""     // the bridge's own selection (selectedId may hold the leaving one)
    property string _bridgeReason: ""

    function _applySnapshot(snap, keepLeaving) {
        root.revision = snap.revision ?? 0
        let list = snap.sessions ?? []
        if (keepLeaving) {
            // gone from the list now: leaving (kept a moment); back: not leaving any more
            const now = Date.now(), ids = new Set(list.map(x => x.id)), lv = Object.assign({}, root._leaving)
            for (const old of root.sessions) if (!ids.has(old.id) && !lv[old.id]) lv[old.id] = { session: old, since: now }
            for (const id of Object.keys(lv)) if (ids.has(id)) delete lv[id]
            root._leaving = lv
            if (Object.keys(lv).length > 0) leaveSweep.start()
            list = list.concat(Object.values(lv).map(x => x.session))
        } else {
            root._leaving = ({})
        }
        root.sessions = list
        root._bridgeSelected = snap.selected_id ?? ""
        root._bridgeReason = snap.selection_reason ?? ""
        root._applySelection()
    }
    // the bridge's selection, unless the selected session is only leaving for a moment
    function _applySelection() {
        if (root._leaving[root.selectedId] && root._bridgeSelected !== root.selectedId) return
        root.selectedId = root._bridgeSelected
        root.selectionReason = root._bridgeReason
    }
    function _left(id, session) {
        if (!session || root._leaving[id]) return
        const lv = Object.assign({}, root._leaving)
        lv[id] = { session: session, since: Date.now() }
        root._leaving = lv
        leaveSweep.start()
    }
    function _back(id) {
        if (!root._leaving[id]) return
        const lv = Object.assign({}, root._leaving)
        delete lv[id]
        root._leaving = lv
    }
    Timer {
        id: leaveSweep
        interval: 500
        repeat: true
        onTriggered: {
            const now = Date.now(), lv = Object.assign({}, root._leaving), gone = []
            for (const id of Object.keys(lv)) if (now - lv[id].since >= root.leaveGraceMs) { delete lv[id]; gone.push(id) }
            if (gone.length > 0) {
                root._leaving = lv
                root.sessions = root.sessions.filter(x => !gone.includes(x.id))
                root._applySelection()
            }
            if (Object.keys(lv).length === 0) stop()
        }
    }

    function _onEvent(ev) {
        if (typeof ev.revision === "number") {
            if (ev.revision <= root.revision) return     // already in the list we have
            root.revision = ev.revision
        }
        switch (ev.type) {
        case "session.added":
        case "session.updated": {
            if (!ev.session) break
            root._back(ev.session_id)
            const list = root.sessions.slice()
            const i = list.findIndex(s => s.id === ev.session_id)
            if (i >= 0) list[i] = ev.session; else list.push(ev.session)
            root.sessions = list
            root._applySelection()
            resync.restart()                // the bridge's order may have changed
            break
        }
        case "session.removed":
            // kept for a moment: it may come straight back (see leaveGraceMs)
            root._left(ev.session_id, root.byId[ev.session_id] ?? ev.session ?? null)
            resync.restart()
            break
        case "selection.changed":
            root._bridgeSelected = ev.session_id ?? ""
            root._bridgeReason = ev.reason ?? ""
            root._applySelection()
            break
        case "provider.status":
        case "provider.removed":
            providersRefresh.restart()
            break
        case "settings.changed":
            root.refreshSettings()
            break
        case "queue.changed":
            if (ev.session_id) root.queueUpdated(ev.session_id)
            break
        case "subscription.closed":
            if (ev.reason !== "shutdown") root._subscribe()
            break
        }                                   // unknown event types are ignored (API.md, Versioning)
    }

    function _subscribe() {
        root.request("subscribe", {}, (err, res) => {
            if (err) {
                if (err.code === "disconnected") return     // the socket's handler deals with that
                root._unavailable("The bridge refused the subscription: " + MediaSources.errorText(err))
                return
            }
            const was = root.state
            root._applySnapshot(res.snapshot ?? {})
            grace.stop()
            root.state = "connected"
            root.problem = ""
            if (was === "reconnecting") console.info("mediasync: reconnected")
            root.resubscribed()
            root.refreshSettings()
            root.refreshProviders()
        })
    }

    function _start() {
        root.request("hello", { client: "quickshell", api_version: 1 }, (err, res) => {
            if (err) {
                if (err.code === "disconnected") return     // the socket's handler deals with that
                root._unavailable(err.code === "invalid_argument" ? "The installed mediasync is too old (needs API 1)"
                                                                   : "The bridge didn't answer: " + MediaSources.errorText(err))
                return
            }
            root.info = res
            root._subscribe()
        })
    }

    // the order and selection, re-read after changes (a list older than what we have is dropped)
    Timer {
        id: resync
        interval: 250
        onTriggered: root.request("sessions.list", {}, (err, res) => {
            if (err || !res || (res.revision ?? 0) < root.revision) return
            root._applySnapshot({ revision: res.revision, sessions: res.sessions,
                                  selected_id: res.selected_id, selection_reason: res.selection_reason }, true)
        })
    }
    Timer { id: providersRefresh; interval: 300; onTriggered: root.refreshProviders() }

    // ── Connection ───────────────────────────────────────────────────────────
    function _clear() {
        root.sessions = []
        root.selectedId = ""
        root.selectionReason = ""
        root.revision = 0
        root.busy = ({})
        root.providers = []
        root.servers = []
        root.diagnostics = null
    }

    // the socket went away or an attempt failed: while there's a snapshot to
    // keep (connected / reconnecting) quietly retry, else unavailable
    function _lost(why) {
        root._failAll("disconnected")
        if (!root.wanted) return
        if (root.state === "connected") {
            console.info("mediasync: connection lost, reconnecting in the background")
            root.state = "reconnecting"
            grace.restart()
        }
        if (root.state === "reconnecting") {
            retry.attempt = 0
            retry.interval = 500
            retry.restart()
            return
        }
        root._unavailable(why)
    }
    Timer {
        id: grace
        interval: root.graceMs
        onTriggered: if (root.state === "reconnecting") root._unavailable("Connection to the bridge lost")
    }

    function _unavailable(why) {
        const was = root.state
        grace.stop()
        if (was === "connected") console.info("mediasync: connection lost, reconnecting in the background")
        else if (was === "reconnecting") console.info("mediasync: still not reachable, showing local players only")
        root._failAll("disconnected")
        root._clear()
        root.state = root.wanted ? "unavailable" : "off"
        root.problem = why
        if (!root.wanted) return
        // the install / service check: when it becomes unavailable, then every 4th attempt (~2 min)
        if (was !== "unavailable" || retry.attempt % 4 === 0) checkInstall.running = true
        retry.schedule()
    }

    Socket {
        id: socket
        path: root.socketPath
        onConnectedChanged: {
            if (connected) {
                retry.attempt = 0
                retry.stop()
                failed.stop()
                if (root.state !== "reconnecting") root.state = "connecting"   // keeps the last state on screen
                root._start()
            } else if (root.state !== "off") {
                root._lost("Connection to the bridge lost")
            }
        }
        parser: SplitParser {
            onRead: line => {
                let msg
                try { msg = JSON.parse(line) } catch (e) { return }
                if (msg.method === "event") root._onEvent(msg.params ?? {})
                else if (msg.id !== undefined && msg.id !== null) {
                    const e = msg.error
                    root._settle(msg.id, e ? { code: e.data?.code ?? "internal_error", message: e.message ?? "" } : null,
                                 e ? null : (msg.result ?? {}))
                }
            }
        }
    }

    // reconnect: 1 s, 2 s, 4 s … 30 s; one attempt at a time, reset once connected
    Timer {
        id: retry
        property int attempt: 0
        function schedule() {
            interval = Math.min(30000, 1000 * Math.pow(2, Math.min(attempt, 5)))
            attempt++
            restart()
        }
        onTriggered: root._attempt()
    }
    Timer {
        id: failed
        interval: 1500
        onTriggered: if (root.wanted && !socket.connected) root._lost(root.problem || "The bridge isn't reachable")
    }

    // only connect when something listens on the socket: every failed connect
    // logs a warning in Quickshell, the bridge may be off for hours, and a
    // killed mediasyncd can leave its socket file behind (ss; else test -S)
    function _attempt() {
        if (!root.wanted || socket.connected || probe.running) return
        if (root.state !== "unavailable" && root.state !== "reconnecting") root.state = "connecting"     // no flicker between attempts
        probe.running = true
    }
    Process {
        id: probe
        command: ["sh", "-c", "if command -v ss >/dev/null; then ss -xlHn src \"$1\" | grep -q .; else test -S \"$1\"; fi",
                  "sh", root.socketPath]
        onExited: code => {
            if (!root.wanted || socket.connected) return
            if (code !== 0 || root.socketPath === "") { root._lost(root.problem || "The bridge isn't running"); return }
            socket.connected = false
            socket.connected = true
            failed.restart()            // no connection within 1.5 s = failed; try again later
        }
    }

    // why it isn't reachable (only while unavailable, not on every attempt)
    Process {
        id: checkInstall
        command: ["sh", "-c", "{ command -v mediasyncd >/dev/null || [ -x \"$HOME/.local/bin/mediasyncd\" ]; } && echo installed || echo missing; systemctl --user is-active mediasyncd 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n")
                root.installState = l[0] ?? ""
                root.serviceState = l[1] ?? ""
                if (root.state !== "unavailable") return
                if (root.installState === "missing") root.problem = "mediasync isn't installed (see MEDIASYNC.md)"
                else if (root.serviceState !== "active" && root.serviceState !== "activating")
                    root.problem = "mediasyncd isn't running (" + (root.serviceState || "unknown") + ")"
                else if (!root.socketPath) root.problem = "XDG_RUNTIME_DIR isn't set, so the socket can't be found"
                else if (root.serviceState === "activating") root.problem = "mediasyncd is starting"
            }
        }
    }

    // try now instead of waiting for the backoff (Settings → Media)
    function reconnect() {
        if (!root.wanted || socket.connected) return
        retry.stop()
        retry.attempt = 0
        if (root.state !== "reconnecting") checkInstall.running = true
        root._attempt()
    }

    // start / restart the user service (Settings → Media)
    Process { id: svc; onExited: { retry.attempt = 0; retry.schedule(); checkInstall.running = true } }
    function serviceAction(action) {
        if (svc.running) return
        svc.command = ["systemctl", "--user", action === "restart" ? "restart" : "start", "mediasyncd"]
        svc.running = true
    }

    function _apply() {
        if (root.wanted) {
            if (socket.connected || retry.running) return
            root.state = "connecting"
            retry.attempt = 0
            root._attempt()
        } else {
            retry.stop()
            failed.stop()
            grace.stop()
            probe.running = false
            const was = root.state
            root.state = "off"
            socket.connected = false
            root._failAll("disconnected")
            root._clear()
            root.problem = ""
            if (was === "connected") console.info("mediasync: off (Settings → Media)")
        }
    }
    onWantedChanged: _apply()
    Component.onCompleted: _apply()
    // a reload drops the old instance: close its connection, nothing waits on it
    Component.onDestruction: {
        retry.stop()
        failed.stop()
        root._pending = ({})
        socket.connected = false
    }
}
