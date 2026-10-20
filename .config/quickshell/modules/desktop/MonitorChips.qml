import QtQuick
import QtQuick.Layouts
import qs.services

// Monitor choice as chips: [Like all widgets] [All monitors] [eDP-1 …] [DP-3 …]
//   value: null (like all widgets, only with allowInherit) | [] (all) | [keys]
// A monitor chip adds / removes that monitor.
Flow {
    id: root
    property var value: []
    property bool allowInherit: false
    signal edited(var value)

    spacing: 6
    readonly property var list: Array.isArray(value) ? value : []

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool on: false
        property bool dim: false
        signal clicked()
        implicitWidth: label.implicitWidth + 22
        implicitHeight: 28
        radius: 14
        color: on ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.25) : mouse.containsMouse ? Colors.fade(0.1) : Colors.fade(0.05)
        border.width: 1
        border.color: on ? Colors.color6 : Colors.fade(0.12)
        Text {
            id: label
            anchors.centerIn: parent
            text: chip.text
            color: chip.dim ? Colors.fade(0.45) : Colors.ink
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    Chip {
        visible: root.allowInherit
        text: "Like all widgets"
        on: root.value === null || root.value === undefined
        onClicked: root.edited(null)
    }
    Chip {
        text: "All monitors"
        on: Array.isArray(root.value) && root.value.length === 0
        onClicked: root.edited([])
    }
    Repeater {
        model: DesktopWidgets.choices(root.list)
        Chip {
            required property var modelData
            text: modelData.label + (modelData.connected ? "" : "  (not connected)")
            dim: !modelData.connected
            on: root.list.includes(modelData.key)
            onClicked: {
                const l = root.list.includes(modelData.key) ? root.list.filter(k => k !== modelData.key) : root.list.concat([modelData.key])
                root.edited(l)
            }
        }
    }
}
