import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Monitor choice as chips: [Like all widgets] [All monitors] [eDP-1 …] [DP-3 …]
//   value: null (like all widgets, only with allowInherit) | [] (all) | [keys]
// A monitor chip adds / removes that monitor.
Flow {
    id: root
    property var value: []
    property bool allowInherit: false
    signal edited(var value)

    spacing: Tokens.space.s6
    readonly property var list: Array.isArray(value) ? value : []

    FilterChip {
        visible: root.allowInherit
        text: "Like all widgets"
        checked: root.value === null || root.value === undefined
        onClicked: root.edited(null)
    }
    FilterChip {
        text: "All monitors"
        checked: Array.isArray(root.value) && root.value.length === 0
        onClicked: root.edited([])
    }
    Repeater {
        model: DesktopWidgets.choices(root.list)
        FilterChip {
            required property var modelData
            text: modelData.label + (modelData.connected ? "" : "  (not connected)")
            dim: !modelData.connected
            checked: root.list.includes(modelData.key)
            onClicked: {
                const l = root.list.includes(modelData.key) ? root.list.filter(k => k !== modelData.key) : root.list.concat([modelData.key])
                root.edited(l)
            }
        }
    }
}
