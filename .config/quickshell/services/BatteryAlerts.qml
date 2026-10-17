pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.services

// Low-battery notifications (settings app → System → Battery, Settings.battery):
//   below `lowLevel` %       → "plug in" every `lowInterval` minutes
//   below `criticalLevel` %  → urgent, every `criticalInterval` minutes
// The first one comes as soon as the level is crossed; each repeat replaces
// the previous notification instead of stacking. Nothing while charging, and
// nothing on machines without a laptop battery.
Singleton {
    id: root

    readonly property var cfg: Settings.battery
    readonly property bool lowOn: cfg.lowAlert ?? true
    readonly property int lowLevel: cfg.lowLevel ?? 20
    readonly property int lowInterval: cfg.lowInterval ?? 5
    readonly property bool criticalOn: cfg.criticalAlert ?? true
    readonly property int criticalLevel: cfg.criticalLevel ?? 10
    readonly property int criticalInterval: cfg.criticalInterval ?? 1

    readonly property var dev: UPower.displayDevice
    readonly property bool present: (dev?.isLaptopBattery ?? false) && (dev?.isPresent ?? true)
    readonly property int level: Math.round((dev?.percentage ?? 1) * 100)
    readonly property bool discharging: dev?.state === UPowerDeviceState.Discharging
                                      || dev?.state === UPowerDeviceState.Empty
                                      || dev?.state === UPowerDeviceState.PendingDischarge

    // "critical" | "low" | ""
    readonly property string tier: !present || !discharging ? ""
        : criticalOn && level <= criticalLevel ? "critical"
        : lowOn && level <= lowLevel ? "low"
        : ""

    property real lastSent: 0
    property string lastTier: ""
    property string notifId: ""          // to replace the previous warning

    onTierChanged: check()
    Timer { running: root.tier !== ""; interval: 15000; repeat: true; onTriggered: root.check() }

    function check() {
        if (tier === "") { lastTier = ""; return }
        const every = (tier === "critical" ? criticalInterval : lowInterval) * 60000
        // right away when the level is crossed (or gets worse), then every `every`
        if (tier !== lastTier || Date.now() - lastSent >= every - 1000) send()
    }

    function timeLeft() {
        const s = dev?.timeToEmpty ?? 0
        if (!(s > 0)) return ""
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    function send() {
        lastSent = Date.now()
        lastTier = tier
        const crit = tier === "critical"
        const left = timeLeft()
        const title = (crit ? "Battery critical" : "Battery low") + " — " + level + "%"
        const body = (crit ? "Plug in the charger now, the laptop will turn off soon."
                           : "Plug in the charger.")
                     + (left !== "" ? " About " + left + " left." : "")
        notifier.command = ["sh", "-c",
            // UTF-8 forced: without a UTF-8 locale notify-send drops titles with "—" etc.
            'LC_ALL=C.UTF-8 notify-send --app-name=Battery --print-id ${3:+--replace-id="$3"}'
            + ' --urgency="$4" --icon="$5" "$1" "$2"',
            "sh", title, body, notifId, crit ? "critical" : "normal",
            crit ? "battery-caution" : "battery-low"]
        notifier.running = true
    }

    // a test from the settings page, whatever the battery does right now
    function test(critical) {
        const t = critical ? "critical" : "low"
        notifier.command = ["sh", "-c", 'LC_ALL=C.UTF-8 notify-send --app-name=Battery --urgency="$3" "$1" "$2"',
            "sh", (critical ? "Battery critical" : "Battery low") + " — test",
            critical ? "This is how the critical warning looks (every " + criticalInterval + " min below " + criticalLevel + "%)."
                     : "This is how the low warning looks (every " + lowInterval + " min below " + lowLevel + "%).",
            critical ? "critical" : "normal"]
        notifier.running = true
    }

    Process {
        id: notifier
        stdout: StdioCollector {
            onStreamFinished: {
                const id = text.trim()
                if (/^\d+$/.test(id)) root.notifId = id
            }
        }
    }
}
