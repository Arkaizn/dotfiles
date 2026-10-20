import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services

// Battery: charge, charging or not, time left (UPower).
RowLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 14
    readonly property var bat: UPower.displayDevice
    readonly property bool present: bat !== null && bat.isLaptopBattery !== false && bat.isPresent !== false
    readonly property int level: Math.round((bat?.percentage ?? 0) * 100)
    readonly property bool charging: bat?.state === UPowerDeviceState.Charging
    readonly property bool full: bat?.state === UPowerDeviceState.FullyCharged
    readonly property color tint: charging || full ? Colors.green : level <= 15 ? Colors.red : level <= 30 ? Colors.yellow : Colors.color6
    function dur(s) { const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return (h > 0 ? h + " h " : "") + m + " min" }

    // the battery shape
    Item {
        implicitWidth: 64; implicitHeight: 32
        Rectangle {
            id: body
            width: 58; height: 32; radius: 7
            color: "transparent"
            border.width: 2
            border.color: Colors.fade(0.5)
            Rectangle {
                x: 4; y: 4
                width: (parent.width - 8) * Math.min(1, root.level / 100)
                height: parent.height - 8; radius: 4
                color: root.tint
            }
        }
        Rectangle { anchors { left: body.right; leftMargin: 1; verticalCenter: body.verticalCenter } width: 4; height: 12; radius: 2; color: Colors.fade(0.5) }
        Text {
            anchors.centerIn: body
            visible: root.charging
            text: "󱐋"
            color: Colors.ink
            font.pixelSize: 16
            font.family: Properties.fontFamily
        }
    }
    ColumnLayout {
        spacing: 2
        Text {
            text: root.present ? root.level + " %" : "No battery"
            color: Colors.ink
            font.pixelSize: 24
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.present
            text: root.full ? "Fully charged"
                : root.charging ? (root.bat.timeToFull > 0 ? "Full in " + root.dur(root.bat.timeToFull) : "Charging")
                : root.bat.timeToEmpty > 0 ? root.dur(root.bat.timeToEmpty) + " left" : "On battery"
            color: Colors.fade(0.6)
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }
    }
}
