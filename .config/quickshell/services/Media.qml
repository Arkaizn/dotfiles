pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services.lib
import QtQuick

// Media players for the bar, dashboard and lockscreen (each view keeps its own
// selected player), and the bar's 3-bar visualizer from cava.
//
//   players                MPRIS players, without playerctld (it only mirrors
//                          the active player, so that one would show up twice)
//   visualizer             [3 heights] while cava runs, else [3, 3, 3]
//   visualizerLive         cava hears sound right now (else the bar plays its
//                          own animation for a playing source)
//   acquireVisualizer() / releaseVisualizer()   cava runs while someone uses
//                          it and a player is playing (one cava for all bars)
//
// Bar and dashboard (MEDIASYNC_PLAN.md, D1–D6):
//   sources                MediaSource objects. With the mediasync bridge
//                          connected: the bridge's sessions (its mode,
//                          discovery, dedup and order), local ones backed by
//                          the native player of the same bus name. Without
//                          it: the native players, as before.
//   bridgeActive           sources come from the bridge
//   selected               the bridge's selected session (or its first one);
//                          null without the bridge (views keep their own pick)
//   selectNext()           select the next source in the bridge
// Lockscreen and desktop widget keep using `players` (native only).
Singleton {
    id: root

    readonly property var players: Mpris.players.values.filter(p => !(p.dbusName || "").includes("playerctld"))
    readonly property bool anyPlaying: players.some(p => p.isPlaying)

    readonly property bool bridgeActive: MediaSync.connected
    readonly property var _sourceDefs: {
        if (!root.bridgeActive)
            return root.players.map(p => ({ key: "native:" + p.dbusName, sessionId: "", mpris: p }))
        return MediaSync.sessions.map(s => {
            const bus = s.provider === "mpris" ? (s.player?.bus_name ?? "") : ""
            const native = bus !== "" ? (root.players.find(p => p.dbusName === bus) ?? null) : null
            return { key: s.id, sessionId: s.id, mpris: native }
        })
    }
    property var sources: []
    function _collect() {
        const out = []
        for (let i = 0; i < sourceInst.count; i++) { const o = sourceInst.objectAt(i); if (o) out.push(o) }
        root.sources = out
    }
    Instantiator {
        id: sourceInst
        model: ScriptModel { values: root._sourceDefs; objectProp: "key" }
        delegate: MediaSource {}
        onObjectAdded: Qt.callLater(root._collect)
        onObjectRemoved: Qt.callLater(root._collect)
    }
    on_SourceDefsChanged: Qt.callLater(root._collect)     // order changes add / remove nothing

    readonly property var selected: root.bridgeActive
        ? (root.sources.find(s => s.sessionId === MediaSync.selectedId) ?? root.sources[0] ?? null) : null
    function selectNext() {
        const ids = root.sources.map(s => s.sessionId)
        const next = MediaSources.nextKey(ids, root.selected?.sessionId ?? "")
        if (next !== "") MediaSync.select(next)
    }

    // what `qs ipc call media …` controls: the bridge's selection, else the playing native player
    readonly property var current: root.selected ?? root.sources.find(s => s.isPlaying) ?? root.sources[0] ?? null

    // qs ipc call media toggle | next | previous | selectNext | select <session id> | seek <s> | status
    IpcHandler {
        target: "media"
        function toggle(): void { root.current?.togglePlaying() }
        function next(): void { root.current?.next() }
        function previous(): void { root.current?.previous() }
        function seek(seconds: real): void { if (root.current?.canSeek) root.current.seek(seconds) }
        function selectNext(): void { root.selectNext() }
        function select(id: string): void { MediaSync.select(id) }
        function status(): string {
            return JSON.stringify({
                bridge: MediaSync.state, problem: MediaSync.problem, current: root.current?.key ?? null,
                nativePlayers: root.players.map(p => p.identity),     // lockscreen / widget (never filtered by the bridge)
                sources: root.sources.map(s => ({ key: s.key, native: s.mpris !== null, origin: s.origin, kind: s.kind,
                    player: s.identity, place: s.placeLabel, title: s.trackTitle, artist: s.trackArtist,
                    playing: s.isPlaying, position: Math.round(s.positionNow()), length: Math.round(s.length),
                    can: ["play", "pause", "next", "previous", "seek", "volume", "shuffle", "loop"].filter(c =>
                        ({ play: s.canPlay, pause: s.canPause, next: s.canGoNext, previous: s.canGoPrevious, seek: s.canSeek,
                           volume: s.canSetVolume, shuffle: s.canShuffle, loop: s.canLoop })[c]) }))
            }, null, 1)
        }
    }

    property int _visualizerUsers: 0
    function acquireVisualizer() { _visualizerUsers++ }
    function releaseVisualizer() { _visualizerUsers = Math.max(0, _visualizerUsers - 1) }

    property var visualizer: [3, 3, 3]
    property bool visualizerLive: false
    // no sound for a second (remote source, muted player): not live
    Timer { id: visualizerQuiet; interval: 1000; onTriggered: root.visualizerLive = false }

    Process {
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/cava/quickshell.ini"]
        running: root._visualizerUsers > 0 && root.anyPlaying
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ")
                if (parts.length !== 3) return
                root.visualizer = parts.map(v => { const n = parseInt(v); return isNaN(n) ? 3 : Math.max(3, n) })
                if (root.visualizer.some(n => n > 3)) { root.visualizerLive = true; visualizerQuiet.restart() }
            }
        }
        onRunningChanged: if (!running) { root.visualizer = [3, 3, 3]; root.visualizerLive = false }
    }
}
