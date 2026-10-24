import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import qs.services
import qs.services.lib
import "parts"

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

    // ── Which monitor shows the lockscreen (Settings → Lockscreen) ──
    // The others show only the blurred wallpaper. No monitors chosen: all of
    // them (as before). Otherwise the first chosen one that's connected, else
    // the one you were using when it locked.
    readonly property var preferred: Settings.lockscreen.monitors ?? []
    property string focusedAtLock: ""
    readonly property string mainScreen: {
        if (preferred.length === 0) return ""
        const names = Quickshell.screens.map(s => s.name)
        const outs = Monitors.outputs
        // an entry is "make model serial", or the output name when that isn't unique (see LockscreenPage)
        const hit = preferred.map(id => outs.find(o => o.ident === id || o.name === id)).find(o => o && names.includes(o.name))
        if (hit) return hit.name
        return names.includes(focusedAtLock) ? focusedAtLock : (names[0] ?? "")
    }
    function showsUi(screenName) { return mainScreen === "" || screenName === mainScreen }
    // monitor names ↔ "make model serial": kept current on every plug / unplug
    Connections { target: Quickshell; function onScreensChanged() { Monitors.refresh() } }

    // No config reload while locked (D11): Quickshell 0.3.2 can't hand a
    // locked WlSessionLock over to the next generation — it unlocks the
    // session, or (locked from the start / not handed over) dies on a Wayland
    // protocol error. So files aren't watched while locked; a QML / JS file
    // saved meanwhile is loaded right after unlocking. Set where the lock
    // changes (not a Binding: Quickshell outlives each config generation, and
    // an old generation's Binding restores its old value when destroyed; and
    // WlSessionLock doesn't always signal `locked` going false).
    onLockedChanged: {
        timing.mark("sessionLock.locked -> " + locked)
        if (!locked) Quickshell.watchFiles = true                   // e.g. the compositor ended the lock
    }
    function reloadIfChanged() {
        Jobs.run(["find", Quickshell.shellDir, "-newermt", "@" + Math.floor(lockedAt / 1000),
                  "(", "-name", "*.qml", "-o", "-name", "*.js", ")", "-print", "-quit"],
                 (code, out) => { if (out.trim() !== "") Quickshell.reload(false) })
    }

    // Caps Lock from the keyboard LEDs, polled while locked
    readonly property bool capsLock: caps.on
    CapsLock { id: caps; active: sessionLock.locked }

    // YubiKey OTP login is set up (services/Yubikey.qml, re-checked on every lock)
    readonly property bool yubikey: Yubikey.present
    // Session.lock() → Panels.open("lockscreen")
    readonly property var api: ({ open: () => root.lock() })
    Component.onCompleted: {
        timing.mark("LockScreen onCompleted")
        Panels.register("lockscreen", api); Quickshell.watchFiles = !locked; Monitors.refresh()
        if (atStart) noteStart()
        if (startPending) lock()
    }

    // Login: niri starts the shell with QS_LOCK_AT_START=1, so it locks from its
    // own start (before: lock.sh polled `qs ipc call lockscreen lock` until the
    // shell answered, showing the desktop meanwhile). shell.qml loads the rest
    // of the shell only once this is shown (startPending), so the lockscreen
    // doesn't wait for it. Only in the first seconds of the shell process: the
    // variable stays set all session, and a later config reload must neither
    // lock nor change how the shell loads.
    // Not after a login on the login screen (greeter/): there you typed the
    // password already. greetd's config says how this session was started
    // (GreeterLib.lockAtStart); lastBoot tells the first session of a boot.
    readonly property bool startPending: atStart && loginLock && !startDone
    property bool startDone: false
    readonly property bool atStart: Quickshell.env("QS_LOCK_AT_START") === "1" && processAge() < 5
    readonly property string bootId: Files.read("/proc/sys/kernel/random/boot_id").trim()
    readonly property string bootFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/login-boot"
    readonly property bool loginLock: GreeterLib.lockAtStart(GreeterLib.greetdMode(Files.read("/etc/greetd/config.toml")),
                                                             bootId, Files.read(bootFile).trim())
    function noteStart() {
        // the boot this login was in; and for lock-watchdog.sh, whether to expect a lock (per niri instance)
        Jobs.run(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s\\n" "$2" > "$1"; ' +
                  'printf "%s %s\\n" "$3" "$NIRI_SOCKET" > "${XDG_RUNTIME_DIR:-/tmp}/quickshell-login-lock"',
                  "sh", bootFile, bootId, loginLock ? "lock" : "none"])
    }
    function processAge() {
        const up = parseFloat(Files.read("/proc/uptime"))
        const ticks = Number(Files.read("/proc/self/stat").replace(/^.*\) /, "").split(" ")[19])    // starttime, field 22
        return up > 0 && ticks > 0 ? up - ticks / 100 : 1e9
    }
    Timer {
        // don't hold the rest of the shell back if locking doesn't happen
        running: root.startPending
        interval: 3000
        onTriggered: root.startDone = true
    }

    Component.onDestruction: Panels.unregister("lockscreen", api)

    function lock() {
        if (sessionLock.locked) return
        timing.mark("lock() called")
        Yubikey.refresh()
        authOpen = false
        password = ""
        checking = false
        failed = false
        status = ""
        unlocking = false
        lockedAt = Date.now()
        Compositor.focusedOutput(name => root.focusedAtLock = name)
        Quickshell.watchFiles = false
        timing.mark("lock(): setting sessionLock.locked = true")
        sessionLock.locked = true
        timing.mark("lock(): sessionLock.locked == " + sessionLock.locked + " (surfaces created)")
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
                root.fail(AuthText.failure(lastMessage, result === PamResult.MaxTries))
            }
        }
        onError: error => {
            root.checking = false
            root.fail(AuthText.error())
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
            Quickshell.watchFiles = true
            root.reloadIfChanged()
            root.authOpen = false
            root.password = ""
            root.unlocking = false
        }
    }

    // TEMPORARY login timing (QS_LOCK_TIMING=1), see LockTiming.qml
    readonly property alias timing: timing
    LockTiming { id: timing }
    Timer { id: timingDone; interval: 2000; onTriggered: timing.finish() }   // lets the journal / rest of the shell catch up

    WlSessionLock {
        id: sessionLock
        // the rest of the shell loads once the lock is shown, not just requested:
        // loading it blocks the GUI thread, which held the first frame back ~0.5 s
        onSecureChanged: if (secure) {
            timing.mark("lock confirmed (sessionLock.secure, surfaces shown)"); timingDone.start()
            root.startDone = true
        }

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
