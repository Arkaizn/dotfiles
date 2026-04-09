//@ pragma UseQApplication

import Quickshell
import QtQuick
import Quickshell.Services.Notifications
// import Quickshell.Io
// import Quickshell.Hyprland
// import Quickshell.Services.SystemTray
// import Quickshell.DBusMenu
// import Quickshell.Widgets

// import QtQuick
// import QtQuick.Controls
// import QtQuick.Layouts
// import QtQuick.Shapes

import "."
import "modules"
import "services" as QsServices
import "modules/notifications"

ShellRoot {
    id: root

    NotificationServer {
    keepOnReload: false
    onNotification: notif => {
        // console.log("notif from:", notif.appName)
        // console.log("summary:", notif.summary)
        // console.log("body:", notif.body)
        notif.tracked = true
        notifPopup.notify(notif.summary, notif.body, notif.appName)
    }
}

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    NotifPopup {id: notifPopup}
}