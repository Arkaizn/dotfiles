pragma Singleton
import Quickshell
import QtQuick
import qs.services
import qs.services.lib

// Settings → Network → "Wi-Fi off while wired" (off by default): Wi-Fi goes
// off while a real wired connection is up (the built-in port or a dock's
// adapter; virtual ones like vmnet don't count) and back on when the cable /
// dock is gone — but only a Wi-Fi this switched off, never one you turned off
// yourself. Waits 3 s, so a short wired drop doesn't toggle the Wi-Fi.
Singleton {
    id: root

    readonly property bool enabled: Settings.network.wifiOffWhenWired ?? false
    readonly property bool wired: NetLink.wiredConnected

    // kept across config reloads, so it still knows it switched the Wi-Fi off
    PersistentProperties {
        id: persist
        reloadableId: "wiredWifi"
        property bool turnedOff: false
    }
    readonly property bool turnedOff: persist.turnedOff

    function update() {
        const a = Devices.wifiAction(enabled, wired, NetLink.wifiEnabled, persist.turnedOff)
        persist.turnedOff = a.turnedOff
        if (a.wifi !== null && a.wifi !== NetLink.wifiEnabled) NetLink.setWifiEnabled(a.wifi)
    }

    Timer { id: settle; interval: 3000; onTriggered: root.update() }
    onWiredChanged: settle.restart()
    onEnabledChanged: update()
    Component.onCompleted: settle.restart()
}
