import Quickshell.Services.Notifications

NotificationServer {
        keepOnReload: false
        onNotification: notif => {
            // console.log("notif from:", notif.appName)
            // console.log("summary:", notif.summary)
            // console.log("body:", notif.body)
            notif.tracked = true
            notifPopup.notify(notif.summary, notif.body, notif.appName, notif.appIcon, notif.actions)
            notifCenter.addNotification(
                Date.now(), notif.summary, notif.body,
                notif.appName, notif.appIcon,
                JSON.stringify(notif.actions ?? [])
            )
        }
        
    }