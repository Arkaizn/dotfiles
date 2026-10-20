import Quickshell
import Quickshell.Networking
import QtQuick
import qs.services
import qs.services.lib
import qs.components

// Left click: control center · right click: Wi-Fi on/off
BarButton {
    id: root

    readonly property var wired: Devices.pick(Networking.devices.values, DeviceType.Wired)
    readonly property var wifi: Devices.pick(Networking.devices.values, DeviceType.Wifi)
    readonly property var wifiNetwork: wifi?.networks?.values.find(n => n.connected) ?? null

    readonly property string wifiIcon: {
        const raw = wifiNetwork?.signalStrength ?? 0
        const s = raw > 1 ? raw / 100 : raw
        if (s > 0.75) return Icons.get("wifi4")
        if (s > 0.5) return Icons.get("wifi3")
        if (s > 0.25) return Icons.get("wifi2")
        return Icons.get("wifi1")
    }

    // One icon per active connection (Ethernet and/or Wi-Fi);
    // nothing connected → crossed-out globe.
    text: {
        const parts = []
        if (wired?.connected) parts.push(Icons.get("wired"))
        if (wifiNetwork) parts.push(wifiIcon)
        return parts.length ? parts.join("  ") : Icons.get("offline")
    }

    buttons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) Networking.wifiEnabled = !Networking.wifiEnabled
        else Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
    }
}
