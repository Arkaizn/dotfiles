import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// The clock card's content: time/date (and batteries under it) on the left;
// on the right its buttons (PanelLayout.ccItems.header — power actions and app
// shortcuts by default) in right-aligned rows of five, so the panel never gets
// wider. Logout / reboot / shut down need a second click within 3s (host.confirm).
// The clock itself stays put; its buttons can be moved while the control
// center's buttons are edited live.
RowLayout {
    id: root

    required property var host           // the control center
    property var batteries: []           // [{ icon, name, level }] from the control center

    readonly property string holderId: "header"
    readonly property var ids: PanelLayout.ccItems.header ?? []
    readonly property var rows: {
        const out = []
        for (let i = 0; i < ids.length; i += 5) out.push(ids.slice(i, i + 5))
        return out
    }
    readonly property Item area: buttons       // where buttons can be dropped
    Component.onCompleted: host.registerHolder(root)
    Component.onDestruction: host.unregisterHolder(root)

    spacing: 6

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
            text: root.host.armed !== ""
                ? "Click again to " + PanelLayout.item(root.host.armed).name.toLowerCase()
                : Time.format("dddd, d. MMMM")
            color: root.host.armed !== "" ? Colors.red : Colors.fade(0.6)
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
        id: buttons
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: root.host.editButtons ? Properties.buttonHeight * 2 + 6 : 0
        Layout.minimumHeight: root.host.editButtons ? Properties.buttonHeight : 0
        spacing: 6

        Repeater {
            model: root.rows
            RowLayout {
                required property var modelData
                Layout.alignment: Qt.AlignRight
                spacing: 6
                Repeater {
                    model: parent.modelData
                    CCItem {
                        required property string modelData
                        itemId: modelData
                        host: root.host
                        compact: true
                    }
                }
            }
        }
    }
}
