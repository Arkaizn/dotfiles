import QtQuick
import QtQuick.Layouts
import QtQml.Models
import qs.services

import "Left"
import "Left/Tray"
import "Middle"
import "Right"

// One zone of the bar: the modules BarLayout puts there for this screen.
// DelegateChooser (not Loader) so a module's own `visible: false` still takes
// it out of the row, spacing included.
RowLayout {
    id: section
    property string screenName
    property string zone
    spacing: Properties.spacing

    Repeater {
        model: BarLayout.layoutFor(section.screenName)[section.zone]
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
