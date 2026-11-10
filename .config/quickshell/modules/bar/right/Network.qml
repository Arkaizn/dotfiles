import Quickshell
import QtQuick
import qs.services
import qs.components

// Left click: control center · right click: Wi-Fi on/off
BarButton {
    id: root

    // NetLink: Quickshell.Networking, or nmcli when that lost NetworkManager
    // (NetworkManager not up yet when the shell started)
    readonly property string wifiIcon: {
        const s = NetLink.wifiSignal
        if (s > 0.75) return Icons.get("wifi4")
        if (s > 0.5) return Icons.get("wifi3")
        if (s > 0.25) return Icons.get("wifi2")
        return Icons.get("wifi1")
    }

    // One icon per active connection (Ethernet and/or Wi-Fi);
    // nothing connected → crossed-out globe.
    text: {
        const parts = []
        if (NetLink.wiredConnected) parts.push(Icons.get("wired"))
        if (NetLink.wifiConnected) parts.push(wifiIcon)
        return parts.length ? parts.join("  ") : Icons.get("offline")
    }

    buttons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) NetLink.setWifiEnabled(!NetLink.wifiEnabled)
        else Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
    }
}
