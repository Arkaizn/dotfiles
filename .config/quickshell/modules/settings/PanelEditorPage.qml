pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "network"

// Panel editor page (Part 6): sizes of the dashboard, control center,
// notification center and each launcher view. Same values as the live editor
// (PanelGeometry → Settings.panels; limits: services/lib/PanelGeom.js).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var lim: PanelGeometry.limits
    readonly property var def: PanelGeometry.defaults

    // one number row: label, the value now, its limits, how to store it
    component SizeRow: NetRow {
        id: row
        property real value: 0
        property real dflt: 0
        property var range: [0, 1]
        property real step: 10
        signal edited(real v)
        changed: value !== dflt
        NumberControl {
            from: row.range[0]
            to: row.range[1]
            step: row.step
            value: row.value
            onEdited: v => row.edited(v)
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Edit live"
        icon: "󰹑"
        NetRow {
            first: true
            label: "Panel editor"
            desc: "Drag the bar to another edge, panels along the bar or off it (floating), resize with the grips. Also: qs ipc call edit panels, or the bar's live edit"
            ActionButton {
                icon: "󰏫"
                text: "Edit live"
                primary: true
                onClicked: { Panels.close("settings"); EditMode.start("panels") }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Bar"
        icon: "󰍜"
        header: ActionButton {
            icon: "󰑓"; text: "Reset"
            interactive: Settings.panels.bar !== undefined
            onClicked: PanelGeometry.reset("bar")
        }
        NetRow {
            first: true
            label: "Screen edge"
            desc: "Every popup comes out of the bar on that edge"
            changed: PanelGeometry.barEdge !== page.def.bar.edge
            Segmented {
                small: true
                options: [{ label: "Top", value: "top" }, { label: "Bottom", value: "bottom" },
                          { label: "Left", value: "left" }, { label: "Right", value: "right" }]
                value: PanelGeometry.barEdge
                onEdited: v => PanelGeometry.set("bar", "edge", v)
            }
        }
        SizeRow {
            label: "Thickness"
            desc: "Its buttons grow with it (button size: Settings → Buttons). Live: the grip under the bar while editing it"
            value: PanelGeometry.barThickness
            dflt: page.def.bar.thickness
            range: page.lim["bar.thickness"]
            step: 2
            onEdited: v => PanelGeometry.set("bar", "thickness", v)
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Dashboard"
        icon: "󰕮"
        header: ActionButton {
            icon: "󰑓"; text: "Reset"
            interactive: Settings.panels.dashboard !== undefined
            onClicked: PanelGeometry.reset("dashboard")
        }
        SizeRow {
            first: true
            label: "Width"
            desc: "The wide column takes what's added; the others stay 300 px"
            value: PanelGeometry.dashboard.width
            dflt: page.def.dashboard.width
            range: page.lim["dashboard.width"]
            onEdited: v => PanelGeometry.set("dashboard", "width", v)
        }
        SizeRow {
            label: "Height"
            desc: PanelGeometry.dashboard.height === 0 ? "As the cards need (" + Math.round(PanelLayout.dashHeight) + " px)"
                : "Never less than the cards need (" + Math.round(PanelLayout.dashHeight) + " px)"
            value: PanelGeometry.dashboard.height === 0 ? PanelLayout.dashHeight : PanelGeometry.dashboard.height
            dflt: PanelGeometry.dashboard.height === 0 ? value : 0
            range: page.lim["dashboard.height"]
            onEdited: v => PanelGeometry.set("dashboard", "height", v <= PanelLayout.dashHeight ? 0 : v)
        }
        PanelPlaceRow { pid: "dashboard" }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Control center"
        icon: "󰒓"
        header: ActionButton {
            icon: "󰑓"; text: "Reset"
            interactive: Settings.panels.controlCenter !== undefined || Settings.panels.notifications !== undefined
            onClicked: { PanelGeometry.reset("controlCenter"); PanelGeometry.reset("notifications") }
        }
        SizeRow {
            first: true
            label: "Width"
            desc: "Cards and their buttons spread out to it"
            value: PanelGeometry.controlCenter.width
            dflt: page.def.controlCenter.width
            range: page.lim["controlCenter.width"]
            onEdited: v => PanelGeometry.set("controlCenter", "width", v)
        }
        SizeRow {
            label: "Notifications"
            desc: "Height: the list grows to this, then scrolls"
            value: PanelGeometry.notifications.height
            dflt: page.def.notifications.height
            range: page.lim["notifications.height"]
            onEdited: v => PanelGeometry.set("notifications", "height", v)
        }
        PanelPlaceRow { pid: "controlCenter" }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Launcher"
        icon: "󰀻"
        header: ActionButton {
            icon: "󰑓"; text: "Reset"
            interactive: Settings.panels.launcher !== undefined
            onClicked: PanelGeometry.reset("launcher")
        }
        NetRow {
            first: true
            label: "Comes from"
            desc: PanelGeometry.launcher.attach === "bar" ? "Out of the bar, like the dashboard"
                : "The screen edge opposite the bar (" + EdgeMap.opposite(PanelGeometry.barEdge) + ")"
            changed: PanelGeometry.launcher.attach !== page.def.launcher.attach
            Segmented {
                small: true
                options: [{ label: "Opposite edge", value: "edge" }, { label: "The bar", value: "bar" }]
                value: PanelGeometry.launcher.attach
                onEdited: v => PanelGeometry.set("launcher", "attach", v)
            }
        }
        Repeater {
            model: [{ v: "apps", name: "Apps" }, { v: "clipboard", name: "Clipboard" }, { v: "connections", name: "Connections" },
                    { v: "wallpapers", name: "Wallpapers" }, { v: "keybinds", name: "Keybinds" }]
            ColumnLayout {
                id: viewRows
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0
                readonly property var size: PanelGeometry.launcherView(modelData.v)
                readonly property var dsize: page.def.launcher.views[modelData.v]
                SizeRow {
                    Layout.fillWidth: true
                    label: viewRows.modelData.name + " · width"
                    value: viewRows.size.w
                    dflt: viewRows.dsize.w
                    range: page.lim["view.w"]
                    onEdited: v => PanelGeometry.setView(viewRows.modelData.v, v, viewRows.size.h)
                }
                SizeRow {
                    Layout.fillWidth: true
                    sub: true
                    label: "height of the list"
                    value: viewRows.size.h
                    dflt: viewRows.dsize.h
                    range: page.lim["view.h"]
                    onEdited: v => PanelGeometry.setView(viewRows.modelData.v, viewRows.size.w, v)
                }
            }
        }
    }
}
