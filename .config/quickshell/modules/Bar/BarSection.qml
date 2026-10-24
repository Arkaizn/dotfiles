import QtQuick
import QtQuick.Layouts
import QtQml.Models
import qs.services

import "Left"
import "Left/Tray"
import "Middle"
import "Right"

// One zone of the bar: the modules BarLayout puts there for this screen.
// A row on a top / bottom bar, a column on a left / right bar (Part 6.7; on a
// vertical bar BarButton turns a module that's wider than the bar).
// DelegateChooser (not Loader / a wrapper) so a module's own `visible: false`
// still takes it out of the row, spacing included.
GridLayout {
    id: section
    property string screenName
    property string zone
    readonly property bool vertical: PanelGeometry.barVertical
    flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    columnSpacing: Properties.spacing
    rowSpacing: Properties.spacing

    // for the live editor (BarEditLayer): the modules' ids and items
    readonly property var ids: BarLayout.layoutFor(section.screenName)[section.zone]
    property bool editing: false        // this bar is edited live: modules wiggle
    property string dragId: ""          // the module being dragged fades
    property int rev: 0                 // bumps when delegates are (re)created
    function itemAt(i) { return rep.itemAt(i) }

    Repeater {
        id: rep
        model: section.ids
        // plain bindings (not Binding elements) so a module always goes back
        // to straight / opaque when editing ends, whatever got rebuilt meanwhile
        onItemAdded: (i, item) => {
            const id = section.ids[i]
            const seed = EditMode.seed(id)
            item.rotation = Qt.binding(() => section.editing && section.dragId !== id ? EditMode.wiggle(seed, 2.4) : 0)
            item.opacity = Qt.binding(() => section.dragId === id ? 0.25 : 1)
            item.Layout.alignment = Qt.AlignCenter
            section.rev++
        }
        onItemRemoved: section.rev++
        delegate: DelegateChooser {
            role: "modelData"
            DelegateChoice { roleValue: "arch"; ArchIcon {} }
            DelegateChoice {
                roleValue: "workspaces"
                Loader {
                    sourceComponent: Compositor.isNiri ? niriWorkspaces : Compositor.isHyprland ? hyprWorkspaces : null
                }
            }
            DelegateChoice { roleValue: "updater"; Updater {} }
            DelegateChoice { roleValue: "pull"; Pull {} }
            DelegateChoice { roleValue: "push"; Push {} }
            DelegateChoice { roleValue: "tray"; Tray {} }
            DelegateChoice { roleValue: "music"; Music {} }
            DelegateChoice { roleValue: "clock"; Clock {} }
            DelegateChoice { roleValue: "cpu"; CPUusage {} }
            DelegateChoice { roleValue: "cputemp"; CPUtemp {} }
            DelegateChoice { roleValue: "mem"; Memusage {} }
            DelegateChoice { roleValue: "gpu"; GPUusage {} }
            DelegateChoice { roleValue: "gputemp"; GPUtemp {} }
            DelegateChoice { roleValue: "headset"; Headset {} }
            DelegateChoice { roleValue: "bluetooth"; Bluetooth {} }
            DelegateChoice { roleValue: "volume"; Volume {} }
            DelegateChoice { roleValue: "network"; Network {} }
            DelegateChoice { roleValue: "notifs"; NotifButton {} }
            DelegateChoice { roleValue: "battery"; Battery {} }
            DelegateChoice { roleValue: "power"; Powermenu {} }
            DelegateChoice { roleValue: "recording"; Recording {} }
            DelegateChoice { roleValue: "capture"; ScreenshotButton {} }
            DelegateChoice { roleValue: "powerprofile"; PowerProfileButton {} }
            DelegateChoice { Item { visible: false } }
        }
    }

    Component { id: niriWorkspaces; Workspaces_niri {} }
    Component { id: hyprWorkspaces; Workspaces_hyprland {} }
}
