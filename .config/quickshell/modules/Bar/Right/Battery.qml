import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import Quickshell.Services.UPower
import qs.services
import qs.components

Item {
    id: root
    implicitWidth: buttonBackground.implicitWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight
    anchors.margins: 1

    property bool hovered: mouseArea.containsMouse
    property bool hasBattery: UPower.displayDevice !== null

    // Hide if no battery devices
    visible: UPower.displayDevice.isLaptopBattery !== false
    
    readonly property var battery: UPower.displayDevice //define battery
    readonly property real percentage: UPower.displayDevice?.percentage ?? 0 // define battery percentage
    readonly property int batteryLevel: Math.round(percentage * 100) // set battery level
    readonly property bool isCharging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

    readonly property color batteryColor: {
        if (isCharging)       return "#4CAF50"  // green
        if (batteryLevel <= 10) return "#F44336" // red
        if (batteryLevel <= 20) return "#FFA726" // orange
        return root.hovered ? Colors.color6 : Colors.foreground
    }

    readonly property string batteryIcon: {
        if (isCharging)        return Icons.get("batCharging") + " "
        if (batteryLevel < 10) return Icons.get("bat10") + " "
        if (batteryLevel < 20) return Icons.get("bat20") + " "
        if (batteryLevel < 40) return Icons.get("bat40") + " "
        if (batteryLevel < 60) return Icons.get("bat60") + " "
        if (batteryLevel < 80) return Icons.get("bat80") + " "
        return Icons.get("batFull") + " "
    }


    ButtonBackground {
        id: buttonBackground
        hovered: root.hovered
        textColor: root.batteryColor
        iconText: hasBattery ? batteryIcon + batteryLevel + "%" : ""
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: buttonBackground.scale = Properties.onEnteredButtonScale
        onExited: buttonBackground.scale = Properties.onExitedButtonScale
        onPressed: buttonBackground.scale = Properties.onPressedButtonScale
        onReleased: buttonBackground.scale = containsMouse ? Properties.onEnteredButtonScale : Properties.onExitedButtonScale
        onCanceled: buttonBackground.scale = Properties.onExitedButtonScale
        cursorShape: Qt.PointingHandCursor
        onClicked: controlCenter.toggle(bar.screen)
    }
}
