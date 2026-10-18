pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Audio preferences shared by the bar, control center and settings app
// (settings → System → Audio). Devices and volumes come from Quickshell's
// Pipewire service; card profiles (stereo / surround / off …) aren't in it, so
// those are read and set with pactl.
//
// Settings.audio: { names: { "<node name>": "alias" }, hidden: ["<node name>"],
//                   step: 5 (scroll %), maxVolume: 100 (up to 150),
//                   sliderScroll: false (wheel over volume sliders) }
Singleton {
    id: root

    readonly property var cfg: Settings.audio
    readonly property real step: Math.max(1, Math.min(20, cfg.step ?? 5)) / 100
    readonly property real maxVolume: Math.max(100, Math.min(150, cfg.maxVolume ?? 100)) / 100
    // mouse wheel over volume sliders changes the volume (default off: it scrolls the page)
    readonly property bool sliderScroll: cfg.sliderScroll ?? false
    readonly property var hidden: Array.isArray(cfg.hidden) ? cfg.hidden : []
    readonly property var names: cfg.names && typeof cfg.names === "object" && !Array.isArray(cfg.names) ? cfg.names : ({})

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource)

    // the name shown everywhere: your alias, else the device's description
    function label(n) {
        if (!n) return "Unknown"
        return names[n.name] || n.description || n.nickname || n.name || "Unknown"
    }
    function isHidden(n) { return !!n && hidden.includes(n.name) }

    function rename(n, alias) {
        const m = Object.assign({}, names)
        alias = String(alias ?? "").trim()
        if (alias === "" || alias === (n.description || n.name)) delete m[n.name]
        else m[n.name] = alias.slice(0, 60)
        Settings.set("audio", "names", m)
    }
    function setHidden(n, on) {
        const h = hidden.filter(x => x !== n.name)
        if (on) h.push(n.name)
        Settings.set("audio", "hidden", h)
    }

    // volume change by the scroll step, capped at maxVolume
    function nudge(audio, up) {
        if (!audio) return
        audio.volume = Math.max(0, Math.min(maxVolume, audio.volume + (up ? step : -step)))
    }

    // ── Card profiles (pactl) ───────────────────────────────────────────────
    // [{ name, description, active, profiles: [{ name, description, available }] }]
    property var cards: []
    property string cardError: ""
    function loadCards() {
        Jobs.run(["pactl", "-f", "json", "list", "cards"], (code, out, err) => {
            if (code !== 0) { cardError = code === 127 ? Jobs.installHint("pactl") : (err.trim() || "pactl failed"); return }
            try {
                cards = JSON.parse(out).map(c => ({
                    name: c.name,
                    description: c.properties?.["device.description"] || c.name,
                    active: c.active_profile,
                    profiles: Object.keys(c.profiles).map(k => ({ name: k, description: c.profiles[k].description, available: c.profiles[k].available }))
                }))
                cardError = ""
            } catch (e) { cardError = "couldn't read pactl's output" }
        })
    }
    function setProfile(card, profile) {
        const c = cards.find(x => x.name === card)
        if (!c || !c.profiles.some(p => p.name === profile)) return
        Jobs.run(["pactl", "set-card-profile", "--", card, profile], () => loadCards())
    }

    // a short sound on a device (pw-play), to find out which one is which
    function testSound(n) {
        Jobs.run(["pw-play", "--target", n.name, "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"], () => {})
    }
}
