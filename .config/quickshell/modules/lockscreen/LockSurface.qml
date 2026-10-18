import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// What one monitor shows while locked.
//
//  idle:  blurred wallpaper, big clock, "press any key", media + notifications
//  auth:  clock moves up and shrinks, password card fades in
//  Any key / click goes idle → auth (the key you pressed is already typed),
//  Esc goes back, 30s without typing goes back on its own.
Item {
    id: root

    required property var lock          // LockScreen (shared state)
    property var screen: null

    readonly property bool auth: lock.authOpen
    // display name from the settings app (Profile), else the user name
    readonly property string user: Settings.profile.name || (Quickshell.env("USER") ?? "")

    // 0 → 1 when locking, 1 → 0 when unlocking (blur, dim, content fade)
    property real shown: 0
    Component.onCompleted: { enterAnim.start(); settleTimer.start(); root.forceActiveFocus() }
    NumberAnimation { id: enterAnim; target: root; property: "shown"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }

    // The surface gets its real size a moment after it's created; the clock's
    // position Behavior would animate that (it slid down from the top), so it
    // only switches on once the layout has settled.
    property bool settled: false
    Timer { id: settleTimer; interval: 120; onTriggered: root.settled = true }
    NumberAnimation { id: exitAnim; target: root; property: "shown"; to: 0; duration: 320; easing.type: Easing.InCubic }
    Connections {
        target: root.lock
        function onUnlockingChanged() { if (root.lock.unlocking) { enterAnim.stop(); exitAnim.start() } }
        function onAuthOpenChanged() {
            if (root.lock.authOpen) passwordField.forceActiveFocus()
            else root.forceActiveFocus()
        }
    }

    // ── Keyboard: any key opens the password view ──
    focus: true
    Keys.onPressed: event => {
        if (root.lock.unlocking) return
        if (!root.auth) {
            root.lock.showAuth()
            if (event.text.length === 1 && event.text.charCodeAt(0) >= 32)
                root.lock.password += event.text
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            root.lock.hideAuth()
            event.accepted = true
        }
    }

    // ── Background: wallpaper that blurs + dims in ──
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.local/share/backgrounds/pywallpaper.png"
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        cache: false
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.shown
        brightness: -0.18 * root.shown
        saturation: -0.1 * root.shown
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.shown * (root.auth ? 0.35 : 0.22)
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // click anywhere (outside the widgets) also opens the password view
    MouseArea {
        anchors.fill: parent
        onClicked: root.lock.showAuth()
    }

    // ── Everything else fades with `shown` ──
    Item {
        id: content
        anchors.fill: parent
        opacity: Math.min(1, root.shown * 1.6)

        // ── Clock ──
        Column {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            // small drop-in from above while locking
            y: (root.auth ? root.height * 0.13 : root.height * 0.5 - height / 2 - 60) - (1 - root.shown) * 30
            scale: root.auth ? 0.6 : 1
            transformOrigin: Item.Top
            spacing: 0
            Behavior on y { enabled: root.settled; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on scale { enabled: root.settled; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text {
                    id: hours
                    text: Time.format("HH")
                    color: "white"
                    font.pixelSize: 168
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    text: ":"
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 168
                    font.family: Properties.fontFamily
                }
                Text {
                    text: Time.format("mm")
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 168
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    anchors.baseline: hours.baseline
                    text: Time.format("ss")
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: 40
                    font.family: Properties.fontFamily
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Time.format("dddd, d. MMMM")
                color: Qt.rgba(1, 1, 1, 0.8)
                font.pixelSize: 26
            }
        }

        // ── "Press any key" hint (idle) ──
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            // sits just above the media card (or near the bottom without one)
            anchors.bottom: media.visible ? media.top : parent.bottom
            anchors.bottomMargin: media.visible ? 28 : 70
            spacing: 6
            opacity: root.auth ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰌾"
                color: "white"
                font.pixelSize: 22
                font.family: Properties.fontFamily
            }
            Text {
                id: hint
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Press any key to unlock"
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: 13
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── Password card (auth) ──
        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height * 0.5 - height / 2 + 40 + (root.auth ? 0 : 30)
            width: 380
            height: cardCol.implicitHeight + 48
            radius: Properties.panelRadius
            color: Properties.panelColor
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
            opacity: root.auth ? 1 : 0
            scale: root.auth ? 1 : 0.94
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            // swallow clicks so they don't hit the background MouseArea
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: cardCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 12

                // avatar
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96
                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: "file://" + Quickshell.env("HOME") + "/.face?r=" + (Settings.profile.faceRev ?? 0)
                        cache: false
                        sourceSize: Qt.size(192, 192)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    OpacityMask {
                        anchors.fill: parent
                        source: avatar
                        maskSource: Rectangle { width: 96; height: 96; radius: 48 }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 48
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Hello, " + root.user
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SearchField {
                        id: passwordField
                        Layout.fillWidth: true
                        icon: "󰌾"
                        password: true
                        placeholderText: root.lock.yubikey ? "Password or YubiKey" : "Password"
                        enabled: !root.lock.checking
                        error: root.lock.failed
                        text: root.lock.password
                        onTextChanged: if (text !== root.lock.password) root.lock.password = text
                        onAccepted: root.lock.submit()
                        Keys.onEscapePressed: root.lock.hideAuth()
                        // keep the cursor at the end when text comes from another screen / the first key
                        onActiveFocusChanged: if (activeFocus) cursorPosition = text.length
                    }
                    IconButton {
                        implicitWidth: Properties.buttonHeight + 4
                        implicitHeight: Properties.buttonHeight + 4
                        icon: root.lock.checking ? "󰔟" : "󰁔"
                        interactive: !root.lock.checking && root.lock.password.length > 0
                        tooltip: "Unlock"
                        onClicked: root.lock.submit()
                    }
                }

                // Caps Lock warning
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: capsText.implicitWidth + 20
                    implicitHeight: root.lock.capsLock ? 24 : 0
                    radius: 12
                    color: "#33fab387"
                    border.width: 1
                    border.color: "#66fab387"
                    opacity: root.lock.capsLock ? 1 : 0
                    visible: implicitHeight > 0.5
                    clip: true
                    Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Text {
                        id: capsText
                        anchors.centerIn: parent
                        text: "󰘲  Caps Lock is on"
                        color: "#fab387"
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 16
                    text: root.lock.status
                    color: root.lock.failed ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 12
                }
            }
        }

        // ── Top-left: when it was locked ──
        Text {
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
                model: BluetoothPower.connected
                delegate: Rectangle {
                    required property var modelData
                    readonly property int level: BluetoothPower.battery(modelData)
                    implicitWidth: btText.implicitWidth + 20
                    implicitHeight: 30
                    radius: Properties.radius
                    color: Properties.panelColor
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.panelBorder
                    Text {
                        id: btText
                        anchors.centerIn: parent
                        text: BluetoothPower.iconFor(modelData) + "  " + modelData.name + (level >= 0 ? "  " + level + "%" : "")
                        color: level >= 0 && level <= 15 ? "#f38ba8" : "white"
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                    }
                }
            }

            Repeater {
                model: {
                    const out = []
                    const d = UPower.displayDevice
                    if (d?.isLaptopBattery) out.push({ icon: "󰁹", level: Math.round(d.percentage * 100) })
                    for (const b of CustomBatteries.available) out.push({ icon: b.icon, level: b.level })
                    return out
                }
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: batText.implicitWidth + 20
                    implicitHeight: 30
                    radius: Properties.radius              // like the buttons, not a full pill
                    color: Properties.panelColor
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.panelBorder
                    Text {
                        id: batText
                        anchors.centerIn: parent
                        text: modelData.icon + "  " + modelData.level + "%"
                        color: modelData.level <= 15 ? "#f38ba8" : "white"
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                    }
                }
            }
        }

        // ── Bottom-centre: media ──
        LockMedia {
            id: media
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 32 }
        }

        // ── Right side: notifications ──
        LockNotifications {
            anchors { right: parent.right; rightMargin: 32; verticalCenter: parent.verticalCenter }
            width: 360
        }

        // ── Bottom-right: power ──
        Row {
            id: power
            anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
            spacing: 8

            property string armed: ""
            Timer { id: disarm; interval: 3000; onTriggered: power.armed = "" }

            Repeater {
                model: [
                    { id: "suspend",  icon: "󰤄", tip: "Suspend",   confirm: false, cmd: "systemctl suspend || loginctl suspend" },
                    { id: "reboot",   icon: "󰜉", tip: "Reboot",    confirm: true,  cmd: "systemctl reboot || loginctl reboot" },
                    { id: "poweroff", icon: "󰐥", tip: "Shut down", confirm: true,  cmd: "systemctl poweroff || loginctl poweroff" }
                ]
                IconButton {
                    required property var modelData
                    implicitWidth: 38; implicitHeight: 38
                    iconSize: 16
                    icon: modelData.icon
                    tooltip: power.armed === modelData.id ? "Click again to " + modelData.tip.toLowerCase() : modelData.tip
                    active: power.armed === modelData.id
                    textColor: power.armed === modelData.id || modelData.id === "poweroff" ? "#f38ba8" : Properties.color
                    onClicked: {
                        if (modelData.confirm && power.armed !== modelData.id) {
                            power.armed = modelData.id
                            disarm.restart()
                            return
                        }
                        power.armed = ""
                        Quickshell.execDetached(["bash", "-c", modelData.cmd])
                    }
                }
            }
        }
    }
}
