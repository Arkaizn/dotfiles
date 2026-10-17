import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

// Small pill with a value (address, MAC, …). Click copies it to the
// clipboard; the pill flashes and says "copied". With `removable` it gets an
// × instead (list editors).
Rectangle {
    id: root
    property string text: ""
    property string label: ""            // dim prefix, e.g. "GW"
    property bool copyable: true
    property bool removable: false
    property bool invalid: false
    property bool accent: false
    signal removed()

    property bool copied: false

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24
    radius: 12
    color: invalid ? Qt.rgba(0.95, 0.55, 0.66, 0.16)
         : copied ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.3)
         : accent ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.14)
         : Qt.rgba(1, 1, 1, mouse.containsMouse && copyable ? 0.12 : 0.07)
    border.width: 1
    border.color: invalid ? Qt.rgba(0.95, 0.55, 0.66, 0.5)
                : accent || copied ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45)
                : Qt.rgba(1, 1, 1, 0.1)
    Behavior on color { ColorAnimation { duration: 160 } }

    // pop in when created (list editors adding a value)
    scale: 0.85
    opacity: 0
    Component.onCompleted: { scale = 1; opacity = 1 }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: root.label !== ""
            text: root.label
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 10
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            text: root.copied ? "copied" : root.text
            color: root.invalid ? "#f38ba8" : "white"
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.removable
            text: "󰅖"
            color: Qt.rgba(1, 1, 1, xMouse.containsMouse ? 0.95 : 0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            MouseArea {
                id: xMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removed()
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.copyable && !root.removable && root.text !== ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.execDetached(["wl-copy", "--", root.text])
            root.copied = true
            copiedTimer.restart()
        }
    }
    Timer { id: copiedTimer; interval: 900; onTriggered: root.copied = false }
}
