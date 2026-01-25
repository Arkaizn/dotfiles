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
    property bool hasBattery: UPower.displayDevice !== null

    // Hide if no battery devices
    visible: hasBattery

    readonly property var battery: UPower.displayDevice
    readonly property real percentage: battery?.percentage ?? 0
    readonly property int batteryLevel: Math.round(percentage * 100)

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

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: root.hovered ? Colors.color4 : Colors.color6
            font.pixelSize: bar.pixelSize
            text: hasBattery ? "󰁹 " + batteryLevel + "%" : ""
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
