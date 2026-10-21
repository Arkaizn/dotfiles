import QtQuick
import Quickshell.Services.Mpris
import qs.services.lib

// One entry of Media.sources: a media session the bar and dashboard can show
// and control, with names like MprisPlayer's so the views stay the same.
//   mpris set      a local player: data and controls through Quickshell's own
//                  MprisPlayer (as before the bridge)
//   only sessionId a bridge session (remote, or a local one without a native
//                  player): data from the bridge, controls through
//                  MediaSync.command with exactly this session's id
// Nothing falls back to another player: a source without a target does nothing.
QtObject {
    id: src

    required property var modelData          // { key, sessionId, mpris } from Media.qml
    readonly property string key: modelData.key
    readonly property string sessionId: modelData.sessionId ?? ""
    readonly property var mpris: modelData.mpris ?? null
    readonly property var session: sessionId !== "" ? (MediaSync.byId[sessionId] ?? null) : null
    readonly property var pb: session?.playback ?? null

    // where it plays
    readonly property string origin: mpris ? "local" : (session?.origin ?? "local")
    readonly property bool remote: origin === "remote"
    readonly property string kind: mpris ? "local" : (session?.kind ?? "")
    readonly property bool viewOnly: !mpris && session !== null && session.controllable !== true
    readonly property bool stale: session?.status === "stale" || session?.status === "disconnected"
    readonly property string placeLabel: remote ? MediaSources.placeLabel(session) : "This device"
    readonly property string kindLabel: mpris ? "on this device" : MediaSources.kindLabel(session)
    readonly property string identity: mpris ? (mpris.identity || "Player")
        : (session?.player?.identity || session?.player?.client || MediaSources.playerName(session))
    readonly property string desktopEntry: mpris ? (mpris.desktopEntry || "") : (session?.player?.desktop_entry ?? "")
    readonly property bool busy: sessionId !== "" && MediaSync.busy[sessionId] === true

    // track
    readonly property string trackTitle: mpris ? (mpris.trackTitle || "") : (session?.track?.title ?? "")
    readonly property string trackArtist: mpris ? (mpris.trackArtist || "") : MediaSources.artists(session)
    readonly property string trackAlbum: mpris ? (mpris.trackAlbum || "") : (session?.track?.album ?? "")
    readonly property string trackArtUrl: mpris ? (mpris.trackArtUrl || "") : MediaArt.get(session?.track?.artwork_url ?? "")
    // changes with the track (the views reset their position on it)
    readonly property string trackKey: trackTitle + "\n" + trackArtist + "\n" + (session?.track?.track_id ?? "")

    // state
    readonly property bool isPlaying: mpris ? mpris.isPlaying : pb?.state === "playing"
    readonly property bool lengthSupported: mpris ? mpris.lengthSupported : (session?.track?.duration_ms ?? 0) > 0
    readonly property real length: mpris ? mpris.length : (session?.track?.duration_ms ?? 0) / 1000     // seconds
    readonly property bool shuffle: mpris ? mpris.shuffle : pb?.shuffle === true
    readonly property var loopState: mpris ? mpris.loopState
        : pb?.repeat === "track" ? MprisLoopState.Track : pb?.repeat === "playlist" ? MprisLoopState.Playlist : MprisLoopState.None
    readonly property real volume: mpris ? mpris.volume : (pb?.volume ?? 0)

    // what can be done (bridge sessions: only what they advertise, D1)
    function _can(c) { return MediaSources.can(src.session, c) }
    readonly property bool canControl: mpris ? mpris.canControl : session?.controllable === true
    readonly property bool canPlay: mpris ? mpris.canPlay : (_can("play") || _can("play_pause"))
    readonly property bool canPause: mpris ? mpris.canPause : (_can("pause") || _can("play_pause"))
    readonly property bool canTogglePlaying: mpris ? mpris.canTogglePlaying : (_can("play_pause") || (_can("play") && _can("pause")))
    readonly property bool canGoNext: mpris ? mpris.canGoNext : _can("next")
    readonly property bool canGoPrevious: mpris ? mpris.canGoPrevious : _can("previous")
    readonly property bool canSeek: mpris ? mpris.canSeek : _can("seek")
    readonly property bool canSetVolume: mpris ? (mpris.volumeSupported && mpris.canControl) : _can("volume")
    // shuffle / repeat / raise: native MPRIS only (the bridge has no commands for them)
    readonly property bool canShuffle: mpris ? (mpris.shuffleSupported && mpris.canControl) : false
    readonly property bool canLoop: mpris ? (mpris.loopSupported && mpris.canControl) : false
    readonly property bool canRaise: mpris ? mpris.canRaise : false

    // position in seconds now; -1 = unknown (e.g. a stale remote session)
    function positionNow() {
        if (src.mpris) return src.mpris.position
        const ms = MediaSources.positionMs(src.session, Date.now())
        return ms < 0 ? -1 : ms / 1000
    }

    // bridge sessions: only what they advertise is sent (else a local error, nothing is sent)
    function _send(ok, name, args) {
        if (ok) MediaSync.command(src.sessionId, name, args)
        else MediaSync.reportError(src.sessionId, { code: src.viewOnly ? "session_not_controllable" : "unsupported_capability", message: "" })
    }

    function play() { if (src.mpris) src.mpris.play(); else src._send(src.canPlay, src._can("play") ? "play" : "play_pause") }
    function pause() { if (src.mpris) src.mpris.pause(); else src._send(src.canPause, src._can("pause") ? "pause" : "play_pause") }
    function togglePlaying() {
        if (src.mpris) src.mpris.togglePlaying()
        else if (src._can("play_pause")) src._send(true, "play_pause")
        else if (src.isPlaying) src.pause()
        else src.play()
    }
    function next() { if (src.mpris) src.mpris.next(); else src._send(src.canGoNext, "next") }
    function previous() { if (src.mpris) src.mpris.previous(); else src._send(src.canGoPrevious, "previous") }
    function seek(seconds) {
        if (src.mpris) src.mpris.position = seconds
        else src._send(src.canSeek, "seek", { position_ms: Math.max(0, Math.round(seconds * 1000)) })
    }
    function setVolume(v) {
        if (src.mpris) src.mpris.volume = v
        else src._send(src.canSetVolume, "set_volume", { volume: Math.max(0, Math.min(1, v)) })
    }
    // local players: as before the bridge (a player that ignores it just doesn't change)
    function setShuffle(on) { if (src.mpris) src.mpris.shuffle = on }
    function setLoop(state) { if (src.mpris) src.mpris.loopState = state }
    function raise() { if (src.canRaise) src.mpris.raise() }
}
