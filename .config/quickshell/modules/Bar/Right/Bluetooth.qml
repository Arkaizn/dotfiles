import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import qs.services
import qs.components

Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    property bool hovered: mouseArea.containsMouse

    visible: true

    readonly property string icon: {
        const adapter = Bluetooth.defaultAdapter
        if (!adapter || !adapter.enabled) return "󰂲"
        if (!adapter.enabling)  return "󰂱"
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
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onClicked: Quickshell.execDetached([
            "bash", "-lc",
            "command -v blueman-manager >/dev/null && blueman-manager || command -v bluetuith >/dev/null && alacritty -e bluetuith || alacritty -e bluetoothctl"
        ])
    }
}
