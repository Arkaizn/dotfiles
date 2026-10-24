import Quickshell
import QtQuick
import qs.services
import "Bar"
import "notifications"
import "dashboard"
import "Launcher"
import "controlcenter"
import "settings"
import "calendar"
import "polkit"
import "capture"
import "wizard"
import "perfmon"
import "desktop"

// Everything in the shell but the lockscreen. A file of its own, loaded by
// shell.qml's LazyLoader through `source`: inline there, all of these modules
// were compiled with shell.qml, before the lockscreen could lock at login.
Scope {
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
    // and the login screen's theme copy (/var/lib/quickshell-greeter)
    readonly property string greeterSync: GreeterSync.status

    DesktopLayer {}

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    NotifPopup {}
    ControlCenter {}
    Launcher {}
    Dashboard {}
    SettingsWindow {}
    CalendarWindow {}
    PolkitDialog {}
    CaptureMenu {}
    Wizard {}
    PerfMonWindow {}
}
