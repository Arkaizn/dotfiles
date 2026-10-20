import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "network"
import "../desktop"

// Desktop widgets page (services/DesktopWidgets.qml): on / off, the monitors
// for all widgets, add widgets, and each widget's monitors and options. Placing,
// rotating and resizing happen in the live editor ("Edit on desktop").
ColumnLayout {
    id: page
    spacing: 16

    property string expanded: ""        // the widget whose options are open
    ConfirmArm { id: arm }

    NetCard {
        Layout.fillWidth: true
        title: "Desktop widgets"
        icon: "󰕮"
        NetRow {
            first: true
            label: "Show desktop widgets"
            desc: "On the wallpaper, below your windows: a window over a widget always gets the click"
            ToggleSwitch { checked: DesktopWidgets.enabled; onToggled: v => DesktopWidgets.setEnabled(v) }
        }
        NetRow {
            label: "Live editor"
            desc: "Drag, rotate and resize on the desktop (hold Ctrl to snap). Or long-press a widget"
            ActionButton {
                icon: "󰏫"
                text: "Edit on desktop"
                primary: true
                interactive: DesktopWidgets.enabled
                onClicked: DesktopWidgets.startEdit("")
            }
        }
        NetRow {
            label: "Show all widgets on"
            desc: "Each widget can also choose its own monitors below"
            wide: true
            MonitorChips {
                Layout.fillWidth: true
                value: DesktopWidgets.monitors
                onEdited: v => DesktopWidgets.setMonitors(v ?? [])
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Add a widget"
        icon: "󰐕"
        NetRow {
            first: true
            wide: true
            label: "Click one to put it in the middle of the screen; place it with the live editor"
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: DesktopWidgets.types
                    ActionButton {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.name
                        onClicked: { const id = DesktopWidgets.add(modelData.type); page.expanded = id }
                    }
                }
            }
        }
    }

    Repeater {
        model: DesktopWidgets.instances
        NetCard {
            id: card
            required property var modelData
            readonly property var info: DesktopWidgets.typeInfo(modelData.type)
            readonly property bool open: page.expanded === modelData.id
            Layout.fillWidth: true
            title: info.name + "  ·  " + modelData.id
            icon: info.icon
            NetRow {
                first: true
                label: card.open ? "Options" : card.info.desc
                desc: Math.round(card.modelData.x * 100) + " % / " + Math.round(card.modelData.y * 100) + " % of the screen"
                      + ((card.modelData.rot ?? 0) !== 0 ? "  ·  " + card.modelData.rot + "°" : "")
                      + ((card.modelData.scale ?? 1) !== 1 ? "  ·  " + Math.round(card.modelData.scale * 100) + " %" : "")
                      + "  ·  " + (card.modelData.monitors === null || card.modelData.monitors === undefined ? "like all widgets"
                                   : card.modelData.monitors.length === 0 ? "all monitors" : card.modelData.monitors.length + " monitor(s)")
                IconButton { icon: card.open ? "󰅃" : "󰅀"; tooltip: card.open ? "Close options" : "Options"; onClicked: page.expanded = card.open ? "" : card.modelData.id }
                IconButton { icon: "󰑓"; tooltip: "Reset rotation and size"; onClicked: DesktopWidgets.update(card.modelData.id, { rot: 0, scale: 1 }) }
                IconButton { icon: "󰆏"; tooltip: "Duplicate"; onClicked: page.expanded = DesktopWidgets.duplicate(card.modelData.id) }
                IconButton {
                    icon: "󰆴"
                    tooltip: arm.armed === card.modelData.id ? "Click again to remove" : "Remove"
                    active: arm.armed === card.modelData.id
                    onClicked: if (arm.confirm(card.modelData.id)) DesktopWidgets.remove(card.modelData.id)
                }
            }
            NetRow {
                visible: card.open
                label: "Monitors"
                wide: true
                MonitorChips {
                    Layout.fillWidth: true
                    allowInherit: true
                    value: card.modelData.monitors ?? null
                    onEdited: v => DesktopWidgets.update(card.modelData.id, { monitors: v })
                }
            }
            Loader {
                active: card.open
                visible: active
                Layout.fillWidth: true
                sourceComponent: WidgetOptions { firstRow: false; instId: card.modelData.id }
            }
        }
    }
}
