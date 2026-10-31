import QtQuick
import qs.services
import qs.components

// Pending updates (click: upgrade). When a reboot is needed (kernel updated)
// it shows that too, in orange; with nothing to update, a click shows the
// reboot notification again (with its Reboot now button).
BarButton {
    visible: Updates.count > 0 || Updates.rebootNeeded
    text: Updates.count > 0 ? Icons.get("updates") + " " + Updates.count + (Updates.rebootNeeded ? " " + Icons.get("reboot") : "") : Icons.get("reboot") + " Reboot"
    iconSize: 14
    textColor: Updates.rebootNeeded ? Colors.orange : Properties.color
    onClicked: Updates.count > 0 ? Updates.upgrade() : Updates.notifyReboot()
}
