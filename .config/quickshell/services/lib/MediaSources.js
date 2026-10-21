.pragma library

// Helpers for mediasync sessions (services/MediaSync.qml, MEDIASYNC.md).
// Session objects are the bridge's schema v1 (~/git/mediasync/docs/API.md):
// unknown values are null, nothing here invents metadata.

// ISO time from the bridge (nanosecond fractions are fine) → ms since epoch, NaN if unknown
function parseTime(s) {
    return typeof s === "string" && s !== "" ? Date.parse(s) : NaN
}

// Current position in ms, extrapolated while playing; -1 = unknown
function positionMs(s, now) {
    const pb = s?.playback
    if (!pb || typeof pb.position_ms !== "number") return -1
    let p = pb.position_ms
    const at = parseTime(pb.position_at)
    if (pb.state === "playing" && !isNaN(at)) p += Math.max(0, now - at) * (typeof pb.rate === "number" ? pb.rate : 1)
    const d = s.track?.duration_ms
    return Math.max(0, typeof d === "number" && d > 0 ? Math.min(p, d) : p)
}

// the session advertises the capability and can be controlled right now
function can(s, cap) {
    return !!s && s.controllable === true && Array.isArray(s.capabilities) && s.capabilities.includes(cap)
}

function playerName(s) {
    const p = s?.player ?? {}
    return p.name || p.identity || p.client || "Unknown player"
}

// short label of where it plays: "This device" / "Test Phone · Finamp"
function placeLabel(s) {
    if (!s) return ""
    if (s.origin === "local") return "This device"
    const p = s.player ?? {}
    return [p.device, p.client].filter(x => x).join(" · ") || "Remote"
}

// what the user can do with it, for badges and descriptions
function kindLabel(s) {
    switch (s?.kind) {
    case "local": return "on this device"
    case "remote_controllable": return "remote"
    case "remote_view_only": return "remote · view only"
    case "stale": return "remote · not reporting"
    case "disconnected": return "server unreachable"
    }
    return s?.origin === "remote" ? "remote" : ""
}

function artists(s) {
    const a = s?.track?.artists
    return Array.isArray(a) ? a.filter(x => x).join(", ") : ""
}

const errorTexts = {
    session_not_found: "That session just ended",
    no_session_selected: "No session selected",
    unsupported_capability: "This player doesn't support that",
    session_not_controllable: "This session can only be watched, not controlled",
    session_unavailable: "The server of this session is unreachable",
    timeout: "The player didn't answer in time",
    provider_error: "The player reported an error",
    provider_unavailable: "That source isn't available",
    provider_not_found: "Unknown server",
    authentication_failed: "Wrong user name or password",
    not_authenticated: "Not logged in",
    invalid_argument: "Invalid value",
    invalid_config: "The bridge's config.toml is invalid",
    credential_store_error: "The keyring failed (locked or prompt dismissed?)",
    credential_store_unavailable: "No keyring (Secret Service) is running",
    server_unreachable: "Can't reach the server",
    tls_error: "The server's TLS certificate isn't trusted",
    internal_error: "Bridge error",
    disconnected: "Lost the connection to the bridge",
    request_timeout: "The bridge didn't answer in time"
}

// error object from MediaSync.request ({ code, message }) → one line for the UI.
// The bridge never puts secrets into messages (API.md, "Errors").
function errorText(err) {
    if (!err) return ""
    const base = errorTexts[err.code] ?? "Error"
    return err.message && err.message !== base ? base + ": " + err.message : base
}

// what the panel shows with these bridge settings → { text, empty }
//   settings: settings.get result { settings: { mode, … }, local_enabled, remote_enabled }
function modeSummary(st) {
    if (!st || !st.settings) return { text: "", empty: false }
    const mode = st.settings.mode
    const local = st.local_enabled !== false && mode !== "remote_only"
    const remote = st.remote_enabled !== false && mode !== "local_only"
    if (local && remote) return { text: "Players on this device and remote sessions", empty: false }
    if (local) return { text: "Only players on this device", empty: false }
    if (remote) return { text: "Only remote sessions", empty: false }
    let why = "nothing: "
    if (mode === "local_only") why += "only local players, but discovery on this device is off"
    else if (mode === "remote_only") why += "only remote sessions, but remote discovery is off"
    else why += "both discoveries are off"
    return { text: why, empty: true }
}

// next key after `current` in `keys` (wraps); first key when current isn't there
function nextKey(keys, current) {
    if (!keys || keys.length === 0) return ""
    const i = keys.indexOf(current)
    return keys[(i + 1) % keys.length]
}

// Jellyfin server URL as the bridge accepts it (CONFIGURATION.md): "" or what's wrong
function serverUrl(u) {
    if (typeof u !== "string" || u.trim() === "") return "enter the server's address"
    const m = /^(https?):\/\/([^\/?#\s]+)(\/[^?#\s]*)?$/.exec(u.trim())
    if (!m) return "use http(s)://host[:port][/path], without ? or #"
    if (m[2].includes("@")) return "no user name or password in the address"
    return ""
}

// server name for config / session IDs: [A-Za-z0-9_-], ≤ 32
function serverName(n) {
    return /^[A-Za-z0-9_-]{1,32}$/.test(n ?? "") ? "" : "letters, digits, - and _ (up to 32)"
}

// m:ss / h:mm:ss for ms; "" when unknown
function clock(ms) {
    if (typeof ms !== "number" || ms < 0 || !isFinite(ms)) return ""
    const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60
    const ss = (s < 10 ? "0" : "") + s
    return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
}
