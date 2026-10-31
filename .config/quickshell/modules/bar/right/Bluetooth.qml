import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.services
import qs.components

// Bluetooth state, followed by an icon per connected device (headset,
// controller, …). Left click: control center · right click: Bluetooth on/off
BarButton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool anyConnected: (adapter?.devices?.values ?? []).some(d => d.connected)

    visible: adapter !== null

    text: {
        if (!adapter?.enabled) return Icons.get("btOff")
        if (anyConnected) return Icons.get("btConnected") + " " + BluetoothPower.connected.map(d => BluetoothPower.iconFor(d)).join(" ")
        return Icons.get("btOn")
    }

    buttons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            BluetoothPower.toggle()
        } else {
            Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
        }
    }
}
