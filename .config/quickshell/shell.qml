//@ pragma UseQApplication

import Quickshell
import QtQuick
import Niri
import Quickshell.Wayland
// import Quickshell.Services.Notifications
// import Quickshell.Io
// import Quickshell.Hyprland
// import Quickshell.Services.SystemTray
// import Quickshell.DBusMenu
// import Quickshell.Widgets

// import QtQuick
// import QtQuick.Controls
// import QtQuick.Layouts
// import QtQuick.Shapes

import "services" as QsServices
import "modules/Bar"
import "modules/notifications"
import "modules/testing"
import "modules/dashboard"
import "modules/Launcher"
import "modules/controlcenter"
import "modules/lockscreen"
import "modules/settings"
import "modules/calendar"
import "modules/polkit"
import "modules/capture"
import "modules/wizard"
import "modules/perfmon"

ShellRoot {
    id: root

    // start the niri settings service with the shell, so its override file
    // follows settings.json even when the settings app isn't open
    readonly property string niriConfig: QsServices.NiriSettings.configDir
    // same for the low-battery notifications
    readonly property string batteryTier: QsServices.BatteryAlerts.tier
    // and the health check (its startup check)
    readonly property int healthErrors: QsServices.Health.errors
    // and the dotfiles IPC target (it runs nothing until called)
    readonly property bool dotfilesRepo: QsServices.Dotfiles.isRepo
    // and the power IPC target / power-saver-on-battery
    readonly property string powerProfile: QsServices.Power.current
    // and the profiles IPC target
    readonly property string settingsProfile: QsServices.SettingsProfiles.active
    // and the theme IPC target (theme apply / undo)
    readonly property bool themeApplying: QsServices.Theme.applying

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // niri's IPC (workspaces in the bar); only connects when running on niri
    Niri {
        id: niri
        Component.onCompleted: if (QsServices.Compositor.isNiri) connect()

        onConnected: console.info("Connected to niri")
        onErrorOccurred: function(error) {
            console.error("Niri error:", error)
        }
    }
    

    NotifPopup {id: notifPopup}
    ControlCenter { id: controlCenter }
    LockScreen { id: lockScreen }
    Launcher { id: launcher }
    Testing {}
    Dashboard {id: dashboard}
    SettingsWindow { id: settingsWindow }
    CalendarWindow { id: calendarWindow }
    PolkitDialog {}
    CaptureMenu {}
    Wizard {}
    PerfMonWindow {}
}