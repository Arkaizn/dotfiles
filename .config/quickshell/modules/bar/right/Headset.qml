import Quickshell
import QtQuick
import qs.services
import qs.components

// Headset battery (from CustomBatteries); hidden while the headset is off.
BarButton {
    id: root

    readonly property int level: CustomBatteries.levelOf("HS80")
    visible: level >= 0

    text: Icons.get("headphones") + "  " + Icons.get("batFull") + " " + root.level + "%"
    onClicked: Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
}
