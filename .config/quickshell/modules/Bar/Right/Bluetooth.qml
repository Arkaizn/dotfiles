import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.services
import qs.components

// Bluetooth state, followed by an icon per connected device (headset,
// controller, …). Left click: control center · right click: Bluetooth on/off
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    property bool hovered: mouseArea.containsMouse

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool anyConnected: (adapter?.devices?.values ?? []).some(d => d.connected)

    visible: adapter !== null

    readonly property string icon: {
        if (!adapter?.enabled) return "󰂲"
        if (anyConnected) return "󰂱 " + BluetoothPower.connected.map(d => BluetoothPower.iconFor(d)).join(" ")
        return "󰂯"
    }

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: root.icon
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                BluetoothPower.toggle()
            } else {
                controlCenter.toggle(bar.screen)
            }
        }
    }
}
