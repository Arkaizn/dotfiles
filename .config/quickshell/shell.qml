//@ pragma UseQApplication

import Quickshell
import QtQuick
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
import "modules/controlcenter"
import "modules/dashboard"

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    NotifServer {}
    NotifPopup {id: notifPopup}
    NotifCenter { id: notifCenter }
    ControlCenter {}
    Dashboard {id: dashboard}
}