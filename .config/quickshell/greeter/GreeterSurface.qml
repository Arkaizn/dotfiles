import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs.services
import "modules/lockscreen/parts"

// What one monitor shows on the login screen: the lockscreen's parts (see
// modules/lockscreen/LockSurface.qml) with the user / session pickers on the
// password card. Left out (no session yet): media, notifications, "locked
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
            onPicked: u => root.lock.chooseUser(u)
        }
        ChoicePicker {
            visible: root.show.sessionPicker && root.lock.sessions.length > 0
            icon: "󰍹"
            model: root.lock.sessions
            current: root.lock.session
            label: s => s.name
            onPicked: s => root.lock.chooseSession(s)
        }
    }

    // ── Top-left: which machine this is ──
    Text {
        visible: root.lock.hostname !== ""
        anchors { left: parent.left; top: parent.top; margins: 32 }
        text: "󰍹  " + root.lock.hostname
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
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
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
        onRun: id => root.lock.power(id)
    }
}
