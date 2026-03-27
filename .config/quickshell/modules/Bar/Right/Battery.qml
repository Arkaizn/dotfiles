import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import Quickshell.Services.UPower
import qs.services
import qs.components

Rectangle {
    id: root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse
    property bool hasBattery: UPower.displayDevice !== null

    // Hide if no battery devices
    visible: UPower.displayDevice.isLaptopBattery !== false
    
    readonly property var battery: UPower.displayDevice //define battery
    readonly property real percentage: UPower.displayDevice?.percentage ?? 0 // define battery percentage
    readonly property int batteryLevel: Math.round(percentage * 100) // set battery level
    readonly property bool isCharging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

    gradient: ButtonGradient {
    hovered: root.hovered
    }

    Behavior on scale {
        NumberAnimation {
            duration: bar.bduration
            easing.type: Easing.OutCubic
        }
    }

    readonly property color batteryColor: {
        if (isCharging)       return "#4CAF50"  // green
        if (batteryLevel <= 10) return "#F44336" // red
        if (batteryLevel <= 20) return "#FFA726" // orange
        return root.hovered ? Colors.color6 : Colors.foreground
    }

    readonly property string batteryIcon: {
        if (isCharging)        return "󰂄 "
        if (batteryLevel < 10) return "󰁺 "
        if (batteryLevel < 20) return "󰁻 "
        if (batteryLevel < 40) return "󰁽 "
        if (batteryLevel < 60) return "󰁿 "
        if (batteryLevel < 80) return "󰂁 "
        return "󰁹 "
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: root.batteryColor
            font.pixelSize: bar.pixelSize
            text: hasBattery ? batteryIcon + batteryLevel + "%" : ""
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = bar.onExitedButtonScale
    }
}
