import Quickshell
import Quickshell.Networking
import QtQuick
import qs.services
import qs.components

// Left click: control center · right click: Wi-Fi on/off
Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight

    property bool hovered: mouseArea.containsMouse

    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifi?.networks?.values.find(n => n.connected) ?? null

    readonly property string wifiIcon: {
        const raw = wifiNetwork?.signalStrength ?? 0
        const s = raw > 1 ? raw / 100 : raw
        if (s > 0.75) return "󰤨"
        if (s > 0.5) return "󰤥"
        if (s > 0.25) return "󰤢"
        return "󰤟"
    }

    // One icon per active connection (Ethernet and/or Wi-Fi);
    // nothing connected → crossed-out globe.
    readonly property string icon: {
        const parts = []
        if (wired?.connected) parts.push("󰌗")
        if (wifiNetwork) parts.push(wifiIcon)
        return parts.length ? parts.join("  ") : "󰪎"
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
            if (mouse.button === Qt.RightButton) Networking.wifiEnabled = !Networking.wifiEnabled
            else controlCenter.toggle(bar.screen)
        }
    }
}
