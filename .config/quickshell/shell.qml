//@ pragma UseQApplication

import Quickshell
import QtQuick
import Quickshell.Wayland
import qs.services
import "modules/Bar"
import "modules/notifications"
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
import "modules/desktop"

ShellRoot {
    id: root

    // start the niri settings service with the shell, so its override file
    // follows settings.json even when the settings app isn't open
    readonly property string niriConfig: NiriSettings.configDir
    // same for the low-battery notifications
    readonly property string batteryTier: BatteryAlerts.tier
    // and the health check (its startup check)
    readonly property int healthErrors: Health.errors
    // and the dotfiles IPC target (it runs nothing until called)
    readonly property bool dotfilesRepo: Dotfiles.isRepo
    // and the VNC server (start with the shell, IPC target, connect notifications)
    readonly property bool vncServer: VncServer.running
    // and the power IPC target / power-saver-on-battery
    readonly property string powerProfile: Power.current
    // and the profiles IPC target
    readonly property string settingsProfile: SettingsProfiles.active
    // and the theme IPC target (theme apply / undo)
    readonly property bool themeApplying: Theme.applying
    // and "Wi-Fi off while wired" (Settings → Network)
    readonly property bool wiredWifi: WiredWifi.turnedOff

    DesktopLayer {}

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    NotifPopup {id: notifPopup}
    ControlCenter { id: controlCenter }
    LockScreen { id: lockScreen }
    Launcher { id: launcher }
    Dashboard {id: dashboard}
    SettingsWindow { id: settingsWindow }
    CalendarWindow { id: calendarWindow }
    PolkitDialog {}
    CaptureMenu {}
    Wizard {}
    PerfMonWindow {}
}