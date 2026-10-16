import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick

// Lockscreen (ext-session-lock): one LockSurface per monitor, all sharing
// the state below (typed password, auth view, errors).
//
// Lock it with:  qs ipc call lockscreen lock   (or scripts/lock.sh)
// There is deliberately no IPC to unlock — only the password does that.
Scope {
    id: root

    // ── Shared state for all surfaces ──
    property bool authOpen: false       // password view instead of the big clock
    property string password: ""
    property bool checking: false
    property bool failed: false         // last attempt was wrong (drives the shake)
    property string status: ""
    property bool unlocking: false      // fade-out running
    property double lockedAt: 0

    readonly property bool locked: sessionLock.locked

    // Caps Lock from the keyboard LEDs (any keyboard), polled while locked
    property bool capsLock: false
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLock = text.split("\n").some(l => parseInt(l) > 0)
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: sessionLock.locked
        triggeredOnStart: true
        onTriggered: if (!capsProc.running) capsProc.running = true
    }

    // YubiKey OTP login is set up: pam_yubico is active in system-auth and the
    // current user has a key in its authfile. Re-checked on every lock.
    property bool yubikey: false
    Process {
        id: yubikeyProc
        command: ["sh", "-c",
            "line=$(grep -E '^[[:space:]]*-?auth[[:space:]].*pam_yubico\\.so' /etc/pam.d/system-auth) || exit 1; " +
            "file=$(printf '%s' \"$line\" | grep -oE 'authfile=[^[:space:]]+' | cut -d= -f2); " +
            "grep -q \"^$USER:\" \"${file:-$HOME/.yubico/authorized_yubikeys}\" 2>/dev/null"]
        onExited: code => root.yubikey = code === 0
    }
    Component.onCompleted: yubikeyProc.running = true

    function lock() {
        if (sessionLock.locked) return
        yubikeyProc.running = true
        authOpen = false
        password = ""
        checking = false
        failed = false
        status = ""
        unlocking = false
        lockedAt = Date.now()
        sessionLock.locked = true
    }

    function showAuth() {
        if (unlocking) return
        authOpen = true
        authIdle.restart()
    }

    function hideAuth() {
        if (checking) return
        authOpen = false
        password = ""
        status = ""
        failed = false
    }

    function submit() {
        if (checking || unlocking || password.length === 0) return
        failed = false
        checking = true
        status = "Checking…"
        pam.lastMessage = ""
        pam.start()
    }

    // back to the clock after 30s without typing
    Timer {
        id: authIdle
        interval: 30000
        onTriggered: if (!root.checking && root.password.length === 0) root.hideAuth()
    }
    onPasswordChanged: if (authOpen) authIdle.restart()

    PamContext {
        id: pam
        configDirectory: Quickshell.shellDir + "/pam"
        config: "password.conf"

        // last info/error text from PAM (e.g. pam_faillock's "account is locked")
        property string lastMessage: ""

        onResponseRequiredChanged: if (responseRequired) respond(root.password)
        onMessageChanged: if (!responseRequired && message) lastMessage = message

        onCompleted: result => {
            root.checking = false
            if (result === PamResult.Success) {
                root.status = ""
                root.unlocking = true
                unlockTimer.restart()
            } else {
                const locked = /lock/i.test(lastMessage)
                root.fail(result === PamResult.MaxTries || locked ? "Too many attempts, wait a moment" : "Wrong password")
            }
        }
        onError: error => {
            root.checking = false
            root.fail("Authentication error")
        }
    }

    function fail(msg) {
        password = ""
        status = msg
        failed = false
        failed = true      // re-trigger the shake
    }

    // let the fade-out play, then really unlock
    Timer {
        id: unlockTimer
        interval: 350
        onTriggered: {
            sessionLock.locked = false
            root.authOpen = false
            root.password = ""
            root.unlocking = false
        }
    }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface
            color: "black"
            LockSurface {
                anchors.fill: parent
                lock: root
                screen: surface.screen
            }
        }
    }

    IpcHandler {
        target: "lockscreen"
        function lock(): void { root.lock() }
        function isLocked(): bool { return sessionLock.locked }
    }
}
