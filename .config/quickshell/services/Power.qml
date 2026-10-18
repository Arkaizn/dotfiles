pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Power profiles (power-profiles-daemon) for the bar module and the settings
// app (System → Power). Reads / sets the profile natively; which profiles
// exist comes from `powerprofilesctl list` (Quickshell's hasPerformanceProfile
// says false on this AMD desktop although performance works).
//
// Settings.power.batterySaver: on battery → power-saver, back on AC → the
// profile from before (only on machines with a battery).
//
//   qs ipc call power get | set <power-saver|balanced|performance> | cycle
Singleton {
    id: root

    readonly property var names: ["power-saver", "balanced", "performance"]
    readonly property var enums: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    readonly property var labels: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })
    readonly property var icons: ({ "power-saver": "󰌪", "balanced": "󰗑", "performance": "󰓅" })

    readonly property string current: names[enums.indexOf(PowerProfiles.profile)] ?? "balanced"
    property var available: []             // from powerprofilesctl; [] = not checked / no daemon
    property bool checked: false
    property string error: ""
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property string degraded: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected ? "the laptop is on your lap"
                                     : PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature ? "it's too hot" : ""

    function check() {
        Jobs.run(["powerprofilesctl", "list"], (code, out, err) => {
            checked = true
            if (code !== 0) { available = []; error = code === 127 ? Jobs.installHint("powerprofilesctl") : (err.trim() || "power-profiles-daemon isn't answering"); return }
            error = ""
            available = names.filter(n => new RegExp("^\\*?\\s*" + n + ":", "m").test(out))
        })
    }
    Component.onCompleted: check()

    function set(name) {
        const i = names.indexOf(name)
        if (i < 0 || (available.length > 0 && !available.includes(name))) return false
        PowerProfiles.profile = enums[i]
        return true
    }
    function cycle() {
        const list = available.length > 0 ? available : ["power-saver", "balanced"]
        set(list[(list.indexOf(current) + 1) % list.length])
    }

    // ── on battery → power saver ────────────────────────────────────────────
    property string beforeBattery: ""
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (!(Settings.power.batterySaver ?? false) || !root.hasBattery) return
            if (UPower.onBattery) { root.beforeBattery = root.current; root.set("power-saver") }
            else if (root.beforeBattery !== "") { root.set(root.beforeBattery); root.beforeBattery = "" }
        }
    }

    IpcHandler {
        target: "power"
        function get(): string { return root.current }
        function set(name: string): string { return root.set(name) ? "now " + name : "unknown or unavailable profile: " + name }
        function cycle(): string { root.cycle(); return root.current }
    }
}
