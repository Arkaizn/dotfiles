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
import "modules/controlcenter"
import "modules/dashboard"
import "modules/Wallpaper"

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Niri {
        id: niri
        Component.onCompleted: connect()

        onConnected: console.info("Connected to niri")
        onErrorOccurred: function(error) {
            console.error("Niri error:", error)
        }
    }
    

    NotifServer {}
    NotifPopup {id: notifPopup}
    NotifCenter { id: notifCenter }
    ControlCenter {}
    Dashboard {id: dashboard}
    WallpaperSelector { id: wallpaperSelector }
}