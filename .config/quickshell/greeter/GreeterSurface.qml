import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs.services
import qs.services.lib
import "modules/lockscreen/parts"

// What one monitor shows on the login screen: the lockscreen's parts (see
// modules/lockscreen/LockSurface.qml) with the user picker above and the session
// picker below the password. Left out (no session yet): media, notifications, "locked
// since", Bluetooth devices, custom batteries.
LockStage {
    id: root

    property var screen: null
    readonly property var show: lock.show

    main: lock.showsUi(screen?.name ?? "")
    wallpaper: lock.wallpaper
    blur: show.blur
    passwordField: card.field

    LockClock {
        stage: root
        seconds: root.show.seconds
        date: root.show.date
    }

    AnyKeyHint {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
        text: "Press any key to log in"
        show: root.show.hint
        auth: root.auth
    }

    AuthCard {
        id: card
        stage: root
        lock: root.lock
        showAvatar: root.show.avatar
        avatar: root.lock.avatar
        greeting: root.lock.displayName === "" ? "" : "Hello, " + root.lock.displayName
        submitTip: "Log in"

        ChoicePicker {
            visible: root.lock.userPicker
            icon: "󰀄"
            model: root.lock.users
            current: root.lock.user
            label: u => u.gecos ? u.gecos + "  (" + u.name + ")" : u.name
            // any other account, also a domain one: typed
            otherLabel: "Other user…"
            otherPlaceholder: "Username  (or name@domain)"
            onPicked: u => { root.lock.chooseUser(u); card.field.forceActiveFocus() }
            onTyped: text => { if (root.lock.chooseUserName(text)) { editing = false; card.field.forceActiveFocus() } }
            onCancelled: card.field.forceActiveFocus()
            onActivity: root.lock.showAuth()        // typing a name keeps the card open
        }
        // what to start, below the password: who and the password stay together
        footer: ChoicePicker {
            visible: root.show.sessionPicker && root.lock.sessions.length > 0
            icon: "󰍹"
            iconOf: s => GreeterLib.sessionIcon(s)
            model: root.lock.sessions
            current: root.lock.session
            label: s => s.name
            onPicked: s => { root.lock.chooseSession(s); card.field.forceActiveFocus() }
        }
    }

    // ── Top-left: which machine this is ──
    Text {
        visible: root.lock.hostname !== ""
        anchors { left: parent.left; top: parent.top; margins: Tokens.space.s32 }
        text: "󰍹  " + root.lock.hostname
        color: Colors.onWallpaper(0.55)
        font.pixelSize: Tokens.font.body
        font.family: Properties.fontFamily
    }

    // ── Top-right: the laptop battery ──
    LockChip {
        readonly property var dev: UPower.displayDevice
        readonly property int level: Math.round((dev?.percentage ?? 0) * 100)
        visible: root.show.batteries && dev?.isLaptopBattery === true
        anchors { right: parent.right; top: parent.top; margins: 28 }
        text: "󰁹  " + level + "%"
        warn: level <= 15
    }

    // ── Bottom-right: power ──
    PowerRow {
        visible: root.show.power
        anchors { right: parent.right; bottom: parent.bottom; margins: Tokens.space.s32 }
        onRun: id => root.lock.power(id)
    }
}
