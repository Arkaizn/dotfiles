import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs.services
import qs.services.lib
import "parts"

// What one monitor shows while locked. Built from the parts the login screen
// (greeter/) shares: LockStage (wallpaper, fade, keys), LockClock,
// AnyKeyHint, AuthCard, LockChip, PowerRow.
//
//  idle:  blurred wallpaper, big clock, "press any key", media + notifications
//  auth:  clock moves up and shrinks, password card fades in
//  Any key / click goes idle → auth (the key you pressed is already typed),
//  Esc goes back, 30s without typing goes back on its own.
LockStage {
    id: root

    property var screen: null

    main: lock.showsUi(screen?.name ?? "")
    wallpaper: Quickshell.env("HOME") + "/.local/share/backgrounds/pywallpaper.png"
    blur: show.blur
    passwordField: card.field

    // display name from the settings app (Profile), else the user name
    readonly property string user: Settings.profile.name || (Quickshell.env("USER") ?? "")
    // what to show (Settings → Lockscreen; services/lib/LockItems.js)
    readonly property var show: LockItems.resolve(Settings.lockscreen)

    LockClock {
        stage: root
        seconds: root.show.seconds
        date: root.show.date
    }

    // sits just above the media card (or near the bottom without one)
    AnyKeyHint {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: media.visible ? media.top : parent.bottom
        anchors.bottomMargin: media.visible ? 28 : 70
        show: root.show.hint
        auth: root.auth
        // FIDO2: a touch unlocks right from here (LockScreen's `touch`)
        text: root.lock.keyMode === "fido2" ? "Press any key or touch your YubiKey" : "Press any key to unlock"
    }

    AuthCard {
        id: card
        stage: root
        lock: root.lock
        showAvatar: root.show.avatar
        avatar: Quickshell.env("HOME") + "/.face?r=" + (Settings.profile.faceRev ?? 0)
        greeting: "Hello, " + root.user
    }

    // ── Top-left: when it was locked ──
    Text {
        visible: root.show.lockedSince
        anchors { left: parent.left; top: parent.top; margins: 32 }
        text: "󰌾  Locked since " + Qt.formatTime(new Date(root.lock.lockedAt), "HH:mm")
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
        font.family: Properties.fontFamily
    }

    // ── Top-right: connected Bluetooth devices, then batteries ──
    Row {
        anchors { right: parent.right; top: parent.top; margins: 28 }
        spacing: 8

        // headset, controller, … with its battery when it reports one
        Repeater {
            model: root.show.bluetooth ? BluetoothPower.connected : []
            delegate: LockChip {
                required property var modelData
                readonly property int level: BluetoothPower.battery(modelData)
                text: BluetoothPower.iconFor(modelData) + "  " + modelData.name + (level >= 0 ? "  " + level + "%" : "")
                warn: level >= 0 && level <= 15
            }
        }

        Repeater {
            model: {
                if (!root.show.batteries) return []
                const d = UPower.displayDevice
                const own = d?.isLaptopBattery ? [{ icon: "󰁹", level: Math.round(d.percentage * 100) }] : []
                return own.concat(CustomBatteries.available.map(b => ({ icon: b.icon, level: b.level })))
            }
            delegate: LockChip {
                required property var modelData
                text: modelData.icon + "  " + modelData.level + "%"
                warn: modelData.level <= 15
            }
        }
    }

    // ── Bottom-centre: media ──
    LockMedia {
        id: media
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 32 }
        visible: root.show.media && player !== null
        controls: root.show.mediaControls
    }

    // ── Right side: notifications ──
    LockNotifications {
        anchors { right: parent.right; rightMargin: 32; verticalCenter: parent.verticalCenter }
        width: 360
        visible: root.show.notifications !== "off" && Notifs.count > 0
        privateMode: root.show.notifications === "private"
    }

    // ── Bottom-right: power ──
    PowerRow {
        visible: root.show.power
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
        onRun: id => id === "suspend" ? Session.suspend() : id === "reboot" ? Session.reboot() : Session.poweroff()
    }
}
