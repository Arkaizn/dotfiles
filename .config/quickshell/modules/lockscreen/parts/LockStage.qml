import Quickshell
import QtQuick
import QtQuick.Effects

// One monitor of the lockscreen or the login screen (greeter): the wallpaper
// that blurs and dims in, the fade in / out, and the keys and clicks that open
// the password view. What's shown on top goes in as children; they fade with
// `shown` and only show on the main monitor.
//
// `lock` is the state shared by all monitors (LockScreen.qml / greeter's
// Greeter.qml): authOpen, password, checking, failed, status, unlocking,
// capsLock, yubikey, keyHint (what to do with the key, under the field),
// emptySubmit (Enter on an empty field is allowed), showAuth(), hideAuth(), submit().
//
//  idle:  any key / click opens the password view (the key is already typed)
//  auth:  Esc goes back; a monitor without the password field types into the
//         shared password
Item {
    id: root

    required property var lock
    // false: another monitor shows the UI, this one only the background (it
    // still takes the keyboard: the password is shared by all monitors)
    property bool main: true
    property string wallpaper: ""
    property bool blur: true
    // the password field to focus when the password view opens (AuthCard.field)
    property Item passwordField: null
    default property alias content: content.data

    readonly property bool auth: lock.authOpen

    // 0 → 1 when shown, 1 → 0 when leaving (blur, dim, content fade)
    property real shown: 0
    Component.onCompleted: { enterAnim.start(); settleTimer.start(); root.forceActiveFocus() }
    NumberAnimation { id: enterAnim; target: root; property: "shown"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }

    // The surface gets its real size a moment after it's created; position
    // Behaviors would animate that (the clock slid down from the top), so they
    // only switch on once the layout has settled.
    property bool settled: false
    Timer { id: settleTimer; interval: 120; onTriggered: root.settled = true }
    NumberAnimation { id: exitAnim; target: root; property: "shown"; to: 0; duration: 320; easing.type: Easing.InCubic }
    Connections {
        target: root.lock
        function onUnlockingChanged() { if (root.lock.unlocking) { enterAnim.stop(); exitAnim.start() } }
        function onAuthOpenChanged() {
            if (root.lock.authOpen && root.main && root.passwordField) root.passwordField.forceActiveFocus()
            else root.forceActiveFocus()
        }
    }

    // ── Keyboard: any key opens the password view ──
    focus: true
    Keys.onPressed: event => { if (root.handleKey(event.key, event.text)) event.accepted = true }
    // returns whether the key was used
    function handleKey(key, text) {
        if (root.lock.unlocking) return false
        if ((!root.main || !root.passwordField) && root.auth) {
            // no password field on this monitor: type into the shared password
            if (key === Qt.Key_Escape) root.lock.hideAuth()
            else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.lock.submit()
            else if (key === Qt.Key_Backspace) root.lock.password = root.lock.password.slice(0, -1)
            else if (text.length === 1 && text.charCodeAt(0) >= 32) root.lock.password += text
            return true
        }
        if (!root.auth) {
            root.lock.showAuth()
            if (text.length === 1 && text.charCodeAt(0) >= 32)
                root.lock.password += text
            return true
        }
        if (key === Qt.Key_Escape) {
            root.lock.hideAuth()
            return true
        }
        return false
    }

    // ── Background: wallpaper that blurs + dims in ──
    Image {
        id: wall
        anchors.fill: parent
        source: root.wallpaper === "" ? "" : "file://" + root.wallpaper
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
        blurEnabled: root.blur
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
        visible: root.main
        opacity: Math.min(1, root.shown * 1.6)
    }
}
