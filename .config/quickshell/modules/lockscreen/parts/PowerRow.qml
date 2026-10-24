pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.services

// Suspend / reboot / shut down, bottom right. Reboot and shut down use the
// power menu's confirm: the first click arms, a second within 3 s runs.
//
//   PowerRow { onRun: id => …("suspend" | "reboot" | "poweroff") }
Row {
    id: root

    signal run(string id)

    spacing: 8

    ConfirmArm { id: arm }
    readonly property string armed: arm.armed

    Repeater {
        model: [
            { id: "suspend",  icon: Icons.get("suspend"), tip: "Suspend",   confirm: false },
            { id: "reboot",   icon: Icons.get("powerReboot"), tip: "Reboot",    confirm: true },
            { id: "poweroff", icon: Icons.get("poweroff"), tip: "Shut down", confirm: true }
        ]
        IconButton {
            id: btn
            required property var modelData
            implicitWidth: 38; implicitHeight: 38
            iconSize: 16
            icon: modelData.icon
            tooltip: root.armed === modelData.id ? "Click again to " + modelData.tip.toLowerCase() : modelData.tip
            active: root.armed === modelData.id
            textColor: root.armed === modelData.id || modelData.id === "poweroff" ? Colors.red : Properties.color
            onClicked: {
                if (btn.modelData.confirm && !arm.confirm(btn.modelData.id)) return
                arm.disarm()
                root.run(btn.modelData.id)
            }
        }
    }
}
