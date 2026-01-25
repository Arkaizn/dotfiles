import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import Quickshell.Services.UPower


import "../../.."

Rectangle {
    id: root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius

    property bool hovered: mouseArea.containsMouse

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.25)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        } 
    }

    // Hide if no battery devices
    visible: hasBattery

    property bool hasBattery: false

    Component.onCompleted: {
        // Check once on load
        checkBattery()
        // Monitor changes
        UPower.UPower.devicesChanged.connect(checkBattery)
    }

    function checkBattery() {
        hasBattery = UPower.UPower.devices.some(function(device) {
            return device.isBattery
        })
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
            // ... existing anchors/properties ...
            text: hasBattery ? "󰁹" + Math.round(UPower.UPower.displayDevice.percent) + "%" : ""
            // No need for Process/Timer—UPower updates reactively
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = onExitedButtonScale
    }
}

