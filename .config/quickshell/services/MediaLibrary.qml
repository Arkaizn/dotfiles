pragma Singleton
import Quickshell
import QtQuick
import qs.services.lib

// Queue, lyrics and playlists of the selected media session, from the
// mediasync bridge (MediaSync; ~/git/mediasync docs/API.md, "Media features").
// For the dashboard's music card; nothing is fetched while nobody uses it.
//
//   acquire() / release()   while a view shows any of it (the dashboard open)
//   source                  the MediaSource it's about (Media.selected)
//   queueShown / lyricsShown / playlistsShown
//                           what the session offers (its capabilities and the
//                           bridge's methods): the views show only these
//   queue    { sessionId, available, currentIndex, items:[…], source, context } | null (loading)
//            context: { type: playlist|album, id, name, shuffled } — only for queues
//            mediasync started (play_items), else null; then items = the whole list
//   lyrics   { sessionId, trackId, status: ok|none|unavailable, synced, lines:[{ startMs, text }], source } | null
//   playlists [{ id, name, count, art, server }] (Audio / unknown media type only)
//   jump(index), playPlaylist(id, mode)   on exactly this session (MediaSync.command)
//
// No polling: the queue is fetched on the bridge's queue.changed and when the
// session changes; lyrics when the track (track_id) or session changes — the
// bridge caches them. After a reconnect everything is fetched again, keeping
// what's shown until the answer is there. Replies for a session / track that
// isn't current any more are dropped (a late answer after a track change).
// Without a capability nothing is asked: queue → { available: false },
// lyrics → status "unavailable".
Singleton {
    id: root

    property int _users: 0
    function acquire() { root._users++ }
    function release() { root._users = Math.max(0, root._users - 1) }
    readonly property bool active: _users > 0 && MediaSync.connected

    readonly property var source: Media.bridgeActive ? Media.selected : null
    readonly property string sessionId: source?.sessionId ?? ""
    readonly property var session: source?.session ?? null

    readonly property bool queueShown: sessionId !== "" && MediaSync.hasMethod("sessions.queue") && (source?.queueish ?? false)
    // only while the shown track really has lyrics (a browser, an instrumental:
    // no button). While the next track's lyrics load the last answer stands,
    // so the button doesn't blink on every track change.
    readonly property bool lyricsShown: sessionId !== "" && MediaSync.hasMethod("lyrics.get")
                                        && (source?.hasLyrics ?? false) && _lyricsOk
    property bool _lyricsOk: false
    onLyricsChanged: if (lyrics !== null) _lyricsOk = lyrics.status === "ok"
    readonly property bool playlistsShown: sessionId !== "" && MediaSync.hasMethod("library.playlists") && (source?.canPlayItems ?? false)
    // play a playlist shuffled: the bridge does it when the session advertises
    // "play_items_shuffle" (play_items with shuffle: true); otherwise a local
    // player whose own shuffle we can switch on first (MPRIS)
    readonly property bool _bridgeShuffle: (session?.capabilities ?? []).includes("play_items_shuffle")
    readonly property bool shuffleShown: playlistsShown && (_bridgeShuffle || (source?.canShuffle ?? false))
    readonly property bool canJump: sessionId !== "" && (source?.canQueueJump ?? false)

    // ── Queue ────────────────────────────────────────────────────────────────
    property var queue: null
    property int pendingJump: -1          // index clicked, until the bridge answers
    property int _queueSeq: 0

    function refreshQueue() {
        const id = root.sessionId
        if (!root.active || id === "") return
        if (!(root.source?.hasQueue ?? false)) {
            root.queue = { sessionId: id, available: false, currentIndex: -1, items: [], source: null }
            return
        }
        const seq = ++root._queueSeq
        MediaSync.request("sessions.queue", { session_id: id }, (err, res) => {
            if (seq !== root._queueSeq || id !== root.sessionId) return     // a newer request, or another session now
            if (err) {
                if (err.code === "disconnected") return                    // resubscribed() asks again
                // session gone / server unreachable: same calm state as no queue
                root.queue = { sessionId: id, available: false, currentIndex: -1, items: [], source: null }
                return
            }
            const items = Array.isArray(res?.items) ? res.items.map((it, i) => ({
                index: typeof it.index === "number" ? it.index : i,
                itemId: it.item_id ?? "",
                title: it.title || "Unknown title",
                artist: Array.isArray(it.artists) ? it.artists.filter(a => a).join(", ") : "",
                album: it.album ?? "",
                durationMs: typeof it.duration_ms === "number" ? it.duration_ms : -1,
                art: it.artwork_url ?? ""
            })) : []
            root.queue = {
                sessionId: id,
                available: res?.available === true && items.length > 0,
                currentIndex: typeof res?.current_index === "number" ? res.current_index : -1,
                items: items,
                source: res?.source ?? null,
                context: res?.context && typeof res.context === "object"
                    ? { type: res.context.type ?? "playlist", id: res.context.id ?? "",
                        name: res.context.name || "", shuffled: res.context.shuffled === true }
                    : null
            }
            root.pendingJump = -1
        })
    }

    // the cover of the queue's context: the playlist's own (from the playlist
    // list, loaded for it), else the first track's (an album)
    // (also while the queue itself isn't known yet: a shuffled playlist waits for
    // the client to report its order, Finamp does on its next track change)
    readonly property var context: queue?.context ?? null
    readonly property string contextArt: {
        const c = root.context
        if (!c) return ""
        const pl = root.playlists.find(p => p.id === c.id)
        return MediaArt.get(pl?.art || (queue?.items?.[0]?.art ?? ""))
    }
    onContextChanged: if (context && context.type === "playlist" && playlists.length === 0) loadPlaylists(false)

    function jump(index) {
        if (!root.canJump || typeof index !== "number") return
        root.pendingJump = index
        MediaSync.command(root.sessionId, "queue_jump", { index: index }, err => {
            root.pendingJump = -1
            if (!err) root.refreshQueue()       // queue.changed may not come when nothing moved
        })
    }

    // ── Lyrics ───────────────────────────────────────────────────────────────
    property var lyrics: null
    property int _lyricsSeq: 0
    readonly property string trackId: session?.track?.track_id ?? ""
    // some local players keep one track id for every track (browsers): the title counts too
    readonly property string _lyricsKey: sessionId + "\n" + trackId + "\n" + (session?.track?.title ?? "")
    property string _lyricsFor: ""          // key of what `lyrics` belongs to

    function refreshLyrics(force) {
        const id = root.sessionId, key = root._lyricsKey, track = root.trackId
        if (!root.active || id === "") return
        if (!force && key === root._lyricsFor && root.lyrics !== null) return
        if (key !== root._lyricsFor) root.lyrics = null       // never show the last track's lyrics
        root._lyricsFor = key
        if (!(root.source?.hasLyrics ?? false)) {
            root.lyrics = { sessionId: id, trackId: track, status: "unavailable", synced: false, lines: [], source: null }
            return
        }
        const seq = ++root._lyricsSeq
        MediaSync.request("lyrics.get", { session_id: id }, (err, res) => {
            if (seq !== root._lyricsSeq || id !== root.sessionId || key !== root._lyricsKey) return
            // a reply for another track than the session plays now (late answer)
            if (!err && (res?.track_id ?? "") !== root.trackId) return
            if (err) {
                if (err.code === "disconnected") { root._lyricsFor = ""; return }   // asked again after the reconnect
                root.lyrics = { sessionId: id, trackId: track, status: "unavailable", synced: false, lines: [], source: null }
                return
            }
            const lines = Array.isArray(res.lines) ? res.lines.map(l => ({
                startMs: typeof l?.start_ms === "number" ? l.start_ms : -1,
                text: typeof l?.text === "string" ? l.text : ""
            })) : []
            const synced = res.synced === true && lines.length > 0 && lines.every(l => l.startMs >= 0)
            root.lyrics = {
                sessionId: id, trackId: track,
                status: res.status === "ok" && lines.length > 0 ? "ok" : (res.status === "none" ? "none" : "unavailable"),
                synced: synced,
                lines: synced ? lines.slice().sort((a, b) => a.startMs - b.startMs) : lines,
                source: res.source ?? null
            }
        })
    }

    // index of the line playing at `ms` (synced lyrics), -1 before the first
    function lineAt(ms) {
        const l = root.lyrics?.lines ?? []
        if (!root.lyrics?.synced || ms < 0 || l.length === 0 || ms < l[0].startMs) return -1
        let lo = 0, hi = l.length - 1
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1
            if (l[mid].startMs <= ms) lo = mid; else hi = mid - 1
        }
        return lo
    }

    // ── Playlists ────────────────────────────────────────────────────────────
    property var playlists: []
    property bool playlistsLoading: false
    property string playlistsError: ""
    property string _playlistsFor: "-"      // server they're from ("" = the only one)
    property real _playlistsAt: 0
    readonly property bool playlistsLoaded: _playlistsAt > 0
    property int _playlistsSeq: 0
    property string playingPlaylist: ""     // id while play_items runs
    property string playedPlaylist: ""      // last one that worked (a check mark for a moment)

    // the selected session's Jellyfin server (with several, the bridge needs it)
    readonly property string server: session?.server?.instance ?? ""

    // fetched when the playlist view opens; again only after 2 min or with force
    function loadPlaylists(force) {
        if (!root.active || !root.playlistsShown) return
        const srv = root.server
        if (!force && srv === root._playlistsFor && Date.now() - root._playlistsAt < 120000) return
        if (srv !== root._playlistsFor) root.playlists = []
        root._playlistsFor = srv
        root.playlistsLoading = true
        root.playlistsError = ""
        const seq = ++root._playlistsSeq
        MediaSync.request("library.playlists", srv !== "" ? { server: srv } : {}, (err, res) => {
            if (seq !== root._playlistsSeq) return
            root.playlistsLoading = false
            if (err) {
                if (err.code === "disconnected") { root._playlistsAt = 0; return }   // keep the list, ask again later
                root.playlistsError = MediaSources.errorText(err)
                root._playlistsAt = 0
                return
            }
            const list = Array.isArray(res?.playlists) ? res.playlists : []
            root.playlists = list
                .filter(p => p && p.id && (p.media_type === null || p.media_type === undefined || p.media_type === "Audio"))
                .map(p => ({ id: p.id, name: p.name || "Untitled playlist",
                             count: typeof p.item_count === "number" ? p.item_count : -1,
                             art: p.artwork_url ?? "", server: p.server ?? "" }))
            root._playlistsAt = Date.now()
        }, 30000)
    }

    // mode: now | next | last; shuffle: in random order (only where shuffleShown)
    function playPlaylist(id, mode, shuffle) {
        if (!root.playlistsShown || !id || root.playingPlaylist !== "") return
        const args = { item_ids: [id], mode: mode || "now" }
        if (shuffle && root._bridgeShuffle) args.shuffle = true
        else if (shuffle && root.source?.canShuffle) root.source.setShuffle(true)
        else if (shuffle) return
        root.playingPlaylist = id
        MediaSync.command(root.sessionId, "play_items", args, err => {
            root.playingPlaylist = ""
            // "acknowledged" is fine too: accepted, the effect just wasn't seen yet
            if (!err) { root.playedPlaylist = id; playedClear.restart() }
        })
    }
    Timer { id: playedClear; interval: 2500; onTriggered: root.playedPlaylist = "" }

    // ── When to fetch ────────────────────────────────────────────────────────
    // one short delay: a session change brings several property changes at once
    Timer { id: queueSoon; interval: 120; onTriggered: root.refreshQueue() }
    Timer { id: lyricsSoon; interval: 150; onTriggered: root.refreshLyrics(false) }

    onSessionIdChanged: {
        root._lyricsOk = false
        root.queue = null
        root.pendingJump = -1
        queueSoon.restart()
        lyricsSoon.restart()
    }
    onActiveChanged: if (active) { queueSoon.restart(); lyricsSoon.restart() }
    on_LyricsKeyChanged: lyricsSoon.restart()
    // capabilities can come and go (a remote control connection, a linked session)
    readonly property string _caps: (source?.hasQueue ? "q" : "") + (source?.hasLyrics ? "l" : "") + (source?.canPlayItems ? "p" : "")
    on_CapsChanged: { queueSoon.restart(); root.refreshLyrics(true) }

    Connections {
        target: MediaSync
        function onQueueUpdated(id) { if (id === root.sessionId) queueSoon.restart() }
        // a new snapshot (e.g. mediasyncd restarted): ask again, keep showing what's there
        function onResubscribed() {
            queueSoon.restart()
            if ((root.lyrics?.status ?? "") !== "ok") root.refreshLyrics(true)
            root._playlistsAt = 0
        }
    }
}
