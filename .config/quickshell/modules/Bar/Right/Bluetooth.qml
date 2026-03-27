import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import qs.services
import qs.components

Rectangle {
    id: root
    implicitWidth: buttonBackground.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse

    visible: true

    readonly property string icon: {
        const adapter = Bluetooth.defaultAdapter
        if (!adapter || !adapter.enabled) return "󰂲"
        if (!adapter.enabling)  return "󰂱"
        return "󰂯"
    }

    gradient: ButtonGradient {
        hovered: root.hovered
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: bar.bduration
            easing.type: Easing.OutCubic
        } 
    }

    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        iconText: root.icon
        iconSize: bar.iconSize
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = bar.onExitedButtonScale
        onClicked: Quickshell.execDetached([
            "bash", "-lc",
            "command -v blueman-manager >/dev/null && blueman-manager || command -v bluetuith >/dev/null && alacritty -e bluetuith || alacritty -e bluetoothctl"
        ])
    }
}
