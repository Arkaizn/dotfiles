import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.lib
import ".."
import "../network"

// Media page: the mediasync bridge (services/MediaSync.qml, MEDIASYNC.md).
// Everything below "Use mediasync" is the bridge's own state, read and changed
// through its API (it persists it); this page keeps no copy of it, and no
// Jellyfin password or token ever lands in Quickshell's settings.
ColumnLayout {
    id: page
    spacing: 16

    readonly property bool on: Settings.media.bridge ?? true
    readonly property bool up: MediaSync.connected
    readonly property var st: MediaSync.settings
    readonly property var pres: st?.settings ?? ({})
    readonly property var summary: MediaSources.modeSummary(st)
    readonly property bool canManageServers: MediaSync.hasMethod("jellyfin.servers.add")
    readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/mediasync/config.toml"

    // every session incl. hidden ones (duplicates, view-only, other mode), for the lists below
    property var all: []
    function refreshAll() {
        if (!page.up) { page.all = []; return }
        MediaSync.listAll((err, res) => { if (!err) page.all = res.sessions ?? [] })
    }
    Timer { id: allRefresh; interval: 300; onTriggered: page.refreshAll() }
    Connections {
        target: MediaSync
        function onSessionsChanged() { allRefresh.restart() }
        function onSettingsChanged() { allRefresh.restart() }
        function onConnectedChanged() { allRefresh.restart(); if (MediaSync.connected) MediaSync.refreshDiagnostics() }
    }
    Component.onCompleted: {
        page.refreshAll()
        if (page.up) { MediaSync.refreshProviders(); MediaSync.refreshDiagnostics() }
        else MediaSync.reconnect()
    }

    // a settings change through the bridge; its answer (or error) shows on the card
    property string settingsError: ""
    function update(changes) {
        page.settingsError = ""
        MediaSync.updateSettings(changes, err => { if (err) page.settingsError = MediaSources.errorText(err) })
    }

    function when(iso) {
        const t = MediaSources.parseTime(iso)
        return isNaN(t) ? "" : new Date(t).toLocaleTimeString(Qt.locale(), "HH:mm:ss")
    }
    function duration(s) {
        if (!(s >= 0)) return ""
        const d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60
        return d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + m + " min" : m + " min"
    }
    readonly property var stateLabels: ({ starting: "starting", running: "connected", degraded: "server unreachable, retrying",
        unauthenticated: "not logged in", error: "error", disabled: "disabled", stopped: "stopped" })

    // ── Bridge ───────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "mediasync bridge"
        icon: "󰝚"
        NetRow {
            first: true
            label: "Use mediasync for the bar and dashboard"
            desc: "Local players and remote sessions (e.g. Jellyfin on your phone) through the bridge. Off: the bar and dashboard show this computer's players directly, as before. The lockscreen and desktop widget always do."
            changed: Settings.has("media", "bridge")
            ToggleSwitch {
                checked: page.on
                onToggled: v => v ? Settings.reset("media", "bridge") : Settings.set("media", "bridge", false)
            }
        }
        NetRow {
            visible: page.on
            label: page.up ? "Connected" : MediaSync.state === "connecting" ? "Connecting…" : "Not connected"
            desc: page.up ? "mediasync " + (MediaSync.info?.version ?? "") + " · API " + (MediaSync.info?.api_version ?? "?")
                            + (MediaSync.diagnostics ? " · running for " + page.duration(MediaSync.diagnostics.uptime_seconds) : "")
                : MediaSync.problem + (MediaSync.state === "unavailable" ? ".  The bar and dashboard show this computer's players meanwhile; it reconnects by itself." : "")
            descError: MediaSync.state === "unavailable"
            ActionButton {
                visible: MediaSync.state === "unavailable" && MediaSync.installState === "installed" && MediaSync.serviceState !== "active"
                icon: "󰐊"; text: "Start service"
                onClicked: MediaSync.serviceAction("start")
            }
            ActionButton {
                visible: MediaSync.state === "unavailable"
                icon: "󰑓"; text: "Retry"
                onClicked: MediaSync.reconnect()
            }
            ActionButton {
                visible: page.up
                icon: "󰜉"; text: "Restart"
                onClicked: MediaSync.serviceAction("restart")
            }
        }
        NetRow {
            visible: page.on && MediaSync.installState === "missing" && !page.up
            wide: true
            label: "Install"
            desc: "git clone https://github.com/Arkaizn/mediasync ~/git/mediasync && cd ~/git/mediasync && make install\nsystemctl --user daemon-reload && systemctl --user enable --now mediasyncd\n(details: MEDIASYNC.md in the Quickshell folder)"
        }
        NetRow {
            visible: page.on
            label: "Configuration"
            desc: "Servers and defaults: " + page.configFile.replace(Quickshell.env("HOME"), "~") + ". Changes on this page are stored by the bridge and win over the file until reset."
            ActionButton { icon: "󰈙"; text: "Open"; onClicked: Quickshell.execDetached(["xdg-open", page.configFile]) }
            ActionButton {
                visible: page.up
                icon: "󰑓"; text: "Reload"
                onClicked: MediaSync.reloadConfig(err => page.settingsError = err ? MediaSources.errorText(err) : "")
            }
        }
        NetRow {
            visible: page.settingsError !== ""
            label: "Couldn't apply"
            desc: page.settingsError
            descError: true
        }
    }

    // ── This device ──────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.on
        enabled: page.up
        opacity: page.up ? 1 : 0.5
        title: "This device"
        icon: "󰌢"
        NetRow {
            first: true
            label: "Discover media players on this device"
            desc: "Automatically discover and display compatible Linux media players running in your current user session, such as Feishin (MPRIS). Off: the bridge stops watching local players; Feishin keeps playing and the lockscreen still shows it."
            ToggleSwitch {
                checked: page.st?.local_enabled ?? true
                onToggled: v => page.update({ local_enabled: v })
            }
        }
        NetRow {
            visible: page.st?.local_enabled ?? true
            sub: true
            label: "Preferred player"
            desc: "Chosen first when it plays, if several do"
            DropdownControl {
                readonly property var locals: page.all.filter(s => s.origin === "local").map(s => {
                    const bus = (s.player?.bus_name ?? "").replace(/^org\.mpris\.MediaPlayer2\./, "").replace(/\.instance.*$/, "")
                    return { label: s.player?.identity || bus || MediaSources.playerName(s), value: (bus || s.player?.identity || "").toLowerCase() }
                }).filter((o, i, a) => o.value !== "" && a.findIndex(x => x.value === o.value) === i)
                readonly property string currentValue: page.pres.preferred_player ?? ""
                options: [{ label: "None", value: "" }].concat(locals,
                    currentValue !== "" && !locals.some(o => o.value === currentValue.toLowerCase()) ? [{ label: currentValue + " (not running)", value: currentValue }] : [])
                value: locals.some(o => o.value === currentValue.toLowerCase()) ? currentValue.toLowerCase() : currentValue
                onEdited: v => page.update({ preferred_player: v })
            }
        }
        Repeater {
            model: page.all.filter(s => s.origin === "local")
            NetRow {
                required property var modelData
                sub: true
                label: MediaSources.playerName(modelData)
                desc: (modelData.playback?.state ?? "unknown") + (modelData.track?.title ? " · " + [MediaSources.artists(modelData), modelData.track.title].filter(x => x).join(" — ") : " · no track info")
                      + " · can: " + ((modelData.capabilities ?? []).join(", ") || "nothing")
            }
        }
        NetRow {
            visible: (page.st?.local_enabled ?? true) && !page.all.some(s => s.origin === "local")
            sub: true
            label: "No players running"
            desc: "Start Feishin (or any MPRIS player) and it shows up here"
        }
    }

    // ── What the panel shows ─────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.on
        enabled: page.up
        opacity: page.up ? 1 : 0.5
        title: "Media panel sources"
        icon: "󰕮"
        NetRow {
            first: true
            label: "Show"
            desc: page.summary.text
            descError: page.summary.empty
            Segmented {
                small: true
                options: [{ label: "This device", value: "local_only", icon: "󰌢" },
                          { label: "Remote", value: "remote_only", icon: Icons.get("mediaRemote") },
                          { label: "Both", value: "combined", icon: "󰕮" }]
                value: page.pres.mode ?? "combined"
                onEdited: v => page.update({ mode: v })
            }
        }
        NetRow {
            wide: true
            label: "When choosing automatically, prefer"
            desc: "Tie-breaker when nothing is selected by hand; a player that starts playing still takes over"
            Segmented {
                small: true
                options: [{ label: "This device", value: "local" }, { label: "Remote", value: "remote" }, { label: "Neither", value: "none" }]
                value: page.pres.prefer_origin ?? "local"
                onEdited: v => page.update({ prefer_origin: v })
            }
        }
        NetRow {
            label: "Show remote sessions that can't be controlled"
            desc: "e.g. a Jellyfin web player without remote control: shown, controls off"
            ToggleSwitch { checked: page.pres.show_view_only ?? true; onToggled: v => page.update({ show_view_only: v }) }
        }
        NetRow {
            label: "Show sessions that stopped reporting"
            desc: "Remote clients that went quiet, and sessions of an unreachable server (position unknown)"
            ToggleSwitch { checked: page.pres.show_stale ?? true; onToggled: v => page.update({ show_stale: v }) }
        }
        NetRow {
            label: "Show the same playback once"
            desc: "Feishin playing from Jellyfin appears as the local player, not twice. Different devices playing the same song are never merged."
            ToggleSwitch { checked: page.pres.dedup ?? true; onToggled: v => page.update({ dedup: v }) }
        }
        NetRow {
            visible: Object.keys(page.st?.overrides ?? {}).length > 0
            label: "Back to config.toml"
            desc: "Changed here: " + Object.keys(page.st?.overrides ?? {}).join(", ")
            ActionButton { icon: "󰦛"; text: "Reset"; onClicked: page.update({ reset: true }) }
        }
    }

    // ── Remote: Jellyfin ─────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.on
        enabled: page.up
        opacity: page.up ? 1 : 0.5
        title: "Remote sessions (Jellyfin)"
        icon: Icons.get("mediaRemote")
        NetRow {
            first: true
            label: "Discover remote sessions"
            desc: "What your Jellyfin clients play on other devices (phone, TV, browser). Off: no server is contacted; local players keep working."
            ToggleSwitch {
                checked: page.st?.remote_enabled ?? true
                onToggled: v => page.update({ remote_enabled: v })
            }
        }
        Repeater {
            // keyed by name: a status refresh updates a row instead of recreating it (typed text, messages)
            model: ScriptModel { values: MediaSync.servers; objectProp: "name" }
            JellyfinServerRow {
                required property var modelData
                server: modelData
                remoteOn: page.st?.remote_enabled ?? true
                canManage: page.canManageServers
                stateLabels: page.stateLabels
                when: page.when
            }
        }
        NetRow {
            visible: MediaSync.servers.length === 0 && !page.canManageServers
            label: "No server configured"
            desc: "Add one to config.toml, e.g.\n[[jellyfin.servers]]\nname = \"home\"\nurl = \"https://jellyfin.example.org\"\nthen Reload above."
        }
        NetRow {
            visible: !page.canManageServers && MediaSync.servers.length > 0
            label: "Add or change servers"
            desc: "Servers live in config.toml (this mediasync has no API to edit them yet). Reload after editing."
            ActionButton { icon: "󰈙"; text: "Open config"; onClicked: Quickshell.execDetached(["xdg-open", page.configFile]) }
        }
        JellyfinAddServer {
            visible: page.canManageServers
        }
        NetRow {
            label: "Reconnecting and refresh"
            // poll_interval_ms: only from bridges that report it (MEDIASYNC.md, gap 3)
            readonly property var pollMs: MediaSync.servers.find(s => typeof s.poll_interval_ms === "number")?.poll_interval_ms
            desc: "The bridge polls each server " + (pollMs ? "every " + (pollMs / 1000) + " s" : "every 2 s by default")
                  + " ([jellyfin] poll_interval in config.toml) and retries an unreachable server by itself; Quickshell reconnects to the bridge by itself (1 s → 30 s)."
        }
    }

    // ── Sessions ─────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.on && page.up
        title: "Sessions"
        icon: "󰐊"
        header: [
            ActionButton {
                visible: MediaSync.selectionReason === "user"
                icon: "󰁨"; text: "Automatic"
                onClicked: MediaSync.select("")
            }
        ]
        Repeater {
            model: page.all
            NetRow {
                id: srow
                required property var modelData
                required property int index
                readonly property bool selected: modelData.id === MediaSync.selectedId
                readonly property string hiddenWhy: ({ duplicate: "shown as the local player", mode: "not in this mode",
                    view_only: "hidden: view only", stale: "hidden: not reporting" })[modelData.hidden ?? ""] ?? (modelData.hidden ? "hidden" : "")
                first: index === 0
                label: (modelData.origin === "remote" ? Icons.get("mediaRemote") + "  " : "") + MediaSources.playerName(modelData)
                desc: [MediaSources.placeLabel(modelData), modelData.origin === "remote" ? MediaSources.kindLabel(modelData) : "", modelData.playback?.state ?? "",
                       modelData.track?.title ? [MediaSources.artists(modelData), modelData.track.title].filter(x => x).join(" — ") : "",
                       srow.hiddenWhy].filter(x => x).join(" · ")
                Chip { visible: srow.selected; text: MediaSync.selectionReason === "user" ? "selected" : "selected (auto)"; accent: true; copyable: false }
                ActionButton {
                    visible: !srow.selected && !modelData.hidden
                    icon: "󰐊"; text: "Select"
                    onClicked: MediaSync.select(modelData.id)
                }
            }
        }
        NetRow {
            visible: page.all.length === 0
            first: true
            label: "Nothing playing"
            desc: "Sessions appear here as soon as a player or a Jellyfin client plays something"
        }
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────
    NetCard {
        id: diagCard
        Layout.fillWidth: true
        visible: page.on && page.up && MediaSync.diagnostics !== null
        title: "Diagnostics"
        icon: "󰛳"
        header: [
            ActionButton { icon: "󰑓"; text: "Refresh"; onClicked: { MediaSync.refreshDiagnostics(); MediaSync.refreshProviders() } },
            ActionButton {
                icon: "󰆏"; text: "Copy"
                // diagnostics.get holds no secrets (API.md)
                onClicked: Quickshell.execDetached(["wl-copy", "--", JSON.stringify(MediaSync.diagnostics, null, 2)])
            }
        ]
        readonly property var d: MediaSync.diagnostics ?? ({})
        NetRow {
            first: true
            label: "Keyring"
            desc: (diagCard.d.credentials?.backend ?? "?") + (diagCard.d.credentials?.available ? " · available" : " · NOT available: Jellyfin login can't store its token")
            descError: !(diagCard.d.credentials?.available ?? true)
        }
        Repeater {
            model: MediaSync.providers
            NetRow {
                required property var modelData
                label: modelData.instance
                desc: (page.stateLabels[modelData.state] ?? modelData.state) + " · " + modelData.sessions + " session(s)"
                      + (modelData.last_success ? " · last ok " + page.when(modelData.last_success) : "")
                      + (modelData.last_error ? "\n" + MediaSources.errorText(modelData.last_error) : "")
                descError: !!modelData.last_error && modelData.state !== "running"
            }
        }
        NetRow {
            label: "Files"
            desc: Object.entries(diagCard.d.paths ?? {}).map(([k, v]) => k.replace(/_/g, " ") + ": " + String(v).replace(Quickshell.env("HOME"), "~")).join("\n")
        }
        NetRow {
            label: "Log"
            desc: "journalctl --user -u mediasyncd -f   ·   mediasyncctl status / list --all / diag"
        }
    }
}
