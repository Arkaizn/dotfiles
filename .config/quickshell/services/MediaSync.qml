pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib

// Connection to the mediasync bridge (~/git/mediasync, docs/API.md): local
// MPRIS players and remote Jellyfin sessions through one socket API.
// MEDIASYNC.md explains setup, MEDIASYNC_PLAN.md the decisions (D1–D8).
//
//   state         "off" (Settings → Media) | "connecting" | "connected" | "unavailable"
//   connected     subscribed, `sessions` is the bridge's current list
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
// requests fail on disconnect or after their timeout. Nothing is kept from a
// lost connection: no stale remote sessions are shown (D6).
Singleton {
    id: root

    readonly property bool wanted: Settings.loaded && (Settings.media.bridge ?? true)
    readonly property string socketPath: Quickshell.env("MEDIASYNC_SOCKET")
        || (Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/mediasync/mediasync.sock" : "")

    property string state: "off"
    readonly property bool connected: state === "connected"
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
            if (err) {
                root.reportError(sessionId, err)
                console.warn("mediasync:", name, "failed:", err.code)
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
            if (!err) { root.selectedId = res.session?.id ?? ""; root.selectionReason = res.reason ?? "" }
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
    function _applySnapshot(snap) {
        root.revision = snap.revision ?? 0
        root.sessions = snap.sessions ?? []
        root.selectedId = snap.selected_id ?? ""
        root.selectionReason = snap.selection_reason ?? ""
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
            const list = root.sessions.slice()
            const i = list.findIndex(s => s.id === ev.session_id)
            if (i >= 0) list[i] = ev.session; else list.push(ev.session)
            root.sessions = list
            resync.restart()                // the bridge's order may have changed
            break
        }
        case "session.removed":
            root.sessions = root.sessions.filter(s => s.id !== ev.session_id)
            resync.restart()
            break
        case "selection.changed":
            root.selectedId = ev.session_id ?? ""
            root.selectionReason = ev.reason ?? ""
            break
        case "provider.status":
        case "provider.removed":
            providersRefresh.restart()
            break
        case "settings.changed":
            root.refreshSettings()
            break
        case "subscription.closed":
            if (ev.reason !== "shutdown") root._subscribe()
            break
        }                                   // unknown event types are ignored (API.md, Versioning)
    }

    function _subscribe() {
        root.request("subscribe", {}, (err, res) => {
            if (err) { root._unavailable("The bridge refused the subscription: " + MediaSources.errorText(err)); return }
            root._applySnapshot(res.snapshot ?? {})
            root.state = "connected"
            root.problem = ""
            root.refreshSettings()
            root.refreshProviders()
        })
    }

    function _start() {
        root.request("hello", { client: "quickshell", api_version: 1 }, (err, res) => {
            if (err) {
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
                                  selected_id: res.selected_id, selection_reason: res.selection_reason })
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

    function _unavailable(why) {
        const was = root.state
        if (was === "connected") console.info("mediasync: connection lost, reconnecting in the background")
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
                root.state = "connecting"
                root._start()
            } else if (root.state !== "off") {
                root._unavailable("Connection to the bridge lost")
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
        onTriggered: if (root.wanted && !socket.connected) root._unavailable(root.problem || "The bridge isn't reachable")
    }

    // only connect when the socket exists: every failed connect logs a warning
    // in Quickshell, and the bridge may be off for hours
    function _attempt() {
        if (!root.wanted || socket.connected || probe.running) return
        if (root.state !== "unavailable") root.state = "connecting"     // no flicker between attempts
        probe.running = true
    }
    Process {
        id: probe
        command: ["test", "-S", root.socketPath]
        onExited: code => {
            if (!root.wanted || socket.connected) return
            if (code !== 0 || root.socketPath === "") { root._unavailable(root.problem || "The bridge isn't running"); return }
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
        checkInstall.running = true
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
