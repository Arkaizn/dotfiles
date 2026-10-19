import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Time/date (and batteries under it) on the left; on the right two rows: power actions, and below
// them shortcuts to the shell's apps (add more to `shortcuts`, they wrap
// onto further rows, right-aligned, so the panel never gets wider).
// Logout / reboot / shut down need a second click within 3s to confirm.
RowLayout {
    id: root

    signal actionStarted()   // lets the control center close itself
    property var batteries: []   // [{ icon, name, level }] from the control center

    spacing: 6

    property string armed: ""   // id of the action waiting for its confirm click

    readonly property var actions: [
        { id: "lock",     icon: Icons.get("lock"), tip: "Lock",      confirm: false,
          cmd: "bash ~/.config/quickshell/scripts/lock.sh" },
        { id: "suspend",  icon: Icons.get("suspend"), tip: "Suspend",   confirm: false,
          cmd: "systemctl suspend || loginctl suspend" },
        { id: "logout",   icon: Icons.get("logout"), tip: "Log out",   confirm: true,
          cmd: Compositor.quitCommand },
        { id: "reboot",   icon: Icons.get("powerReboot"), tip: "Reboot",    confirm: true,
          cmd: "systemctl reboot || loginctl reboot" },
        { id: "poweroff", icon: Icons.get("poweroff"), tip: "Shut down", confirm: true,
          cmd: "systemctl poweroff || loginctl poweroff" }
    ]

    // each runs `qs ipc call <call…>`
    readonly property var shortcuts: [
        { icon: "󰌌", tip: "Keybinds", call: ["Launcher", "toggleKeybinds"] },
        { icon: "󰒓", tip: "Settings", call: ["settings", "open"] }
    ]

    function run(a) {
        if (a.confirm && root.armed !== a.id) {
            root.armed = a.id
            disarmTimer.restart()
            return
        }
        root.armed = ""
        root.actionStarted()
        Quickshell.execDetached(["bash", "-c", a.cmd])
    }

    Timer { id: disarmTimer; interval: 3000; onTriggered: root.armed = "" }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: -2
        Text {
            text: Time.format("HH:mm:ss")
            color: Colors.ink
            font.pixelSize: 30
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            text: root.armed !== ""
                ? "Click again to " + root.actions.find(a => a.id === root.armed).tip.toLowerCase()
                : Time.format("dddd, d. MMMM")
            color: root.armed !== "" ? Colors.red : Colors.fade(0.6)
            font.pixelSize: 12
        }
        // batteries
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: root.batteries.length > 0
            spacing: 6
            Repeater {
                model: root.batteries
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: chip.implicitWidth + 16
                    implicitHeight: 24
                    radius: Properties.radius
                    color: Colors.card
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.cardBorder
                    Text {
                        id: chip
                        anchors.centerIn: parent
                        text: modelData.icon + "  " + modelData.name + "  " + modelData.level + "%"
                        color: modelData.level <= 15 ? Colors.red : modelData.level <= 30 ? Colors.orange : Colors.ink
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                    }
                }
            }
        }
    }

    // takes the spare width (the time column can't grow past its text), so the
    // buttons sit flush right with the same margin as the time on the left
    Item { Layout.fillWidth: true }

    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 6

        RowLayout {
            id: powerRow
            Layout.alignment: Qt.AlignRight
            spacing: 6
            Repeater {
                model: root.actions
                IconButton {
                    required property var modelData
                    icon: modelData.icon
                    tooltip: modelData.tip
                    active: root.armed === modelData.id
                    textColor: root.armed === modelData.id || modelData.id === "poweroff" ? Colors.red : Properties.color
                    onClicked: root.run(modelData)
                }
            }
        }

        // as wide as the power row; right to left so a short last row sits on
        // the right (the list is reversed to keep its order left → right)
        Flow {
            Layout.preferredWidth: powerRow.implicitWidth
            layoutDirection: Qt.RightToLeft
            spacing: 6
            Repeater {
                model: root.shortcuts.slice().reverse()
                IconButton {
                    required property var modelData
                    icon: modelData.icon
                    tooltip: modelData.tip
                    onClicked: {
                        root.actionStarted()
                        Quickshell.execDetached(["qs", "ipc", "call"].concat(modelData.call))
                    }
                }
            }
        }
    }
}
