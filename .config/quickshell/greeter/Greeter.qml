import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import Qt.labs.folderlistmodel
import QtQuick
import qs.services
import qs.services.lib
import "modules/lockscreen/parts"

// Login screen on greetd: the lockscreen's look (the parts in
// modules/lockscreen/parts), with a user and session picker. Runs as the
// `greeter` user inside its own niri (greeter/system/), so it can't read your
// home: everything it shows comes from /var/lib/quickshell-greeter/theme,
// written by the shell (services/GreeterSync.qml).
//
// One ext-session-lock surface per monitor (like the lockscreen): niri gives
// it all input and shows nothing else. There is no IPC.
//
// Environment (greeter/system/runner sets these):
//   GREETD_SOCK         greetd's socket (Quickshell.Services.Greetd)
//   QS_GREETER_DATA     theme dir: wallpaper.jpg, face.png, meta.json
//   QS_GREETER_STATE    writable: last.json { user, session }
//   QS_GREETER_RUN      runtime dir: "ready" once shown, "launched" before launching
//   QS_GREETER_DRYRUN=1 power buttons only log (tests)
Scope {
    id: root

    readonly property string dataDir: Quickshell.env("QS_GREETER_DATA") || "/var/lib/quickshell-greeter/theme"
    readonly property string stateDir: Quickshell.env("QS_GREETER_STATE") || "/var/lib/quickshell-greeter/state"
    readonly property string runDir: Quickshell.env("QS_GREETER_RUN") || ""
    readonly property bool dryRun: Quickshell.env("QS_GREETER_DRYRUN") === "1"

    // ── Shared state for all surfaces (same names as LockScreen, see LockStage) ──
    property bool authOpen: false
    property string password: ""
    property bool checking: false
    property bool failed: false
    property string status: ""
    property bool unlocking: false
    readonly property bool capsLock: caps.on
    // the owner's YubiKey login (services/Yubikey.qml, via meta.json): greetd runs one PAM
    // conversation (system-auth: password first, then the key), so unlike the lockscreen
    // nothing listens for a touch on its own. FIDO2: Enter on the empty field fails the
    // password at once, then pam_u2f waits for the touch ("Please touch the device")
    readonly property string keyMode: !isOwner ? "none" : meta.yubikeyMode ?? (meta.yubikey === true ? "otp" : "none")
    readonly property bool yubikey: keyMode !== "none"
    readonly property string keyHint: keyMode === "fido2" ? "…or Enter with an empty field, then touch your YubiKey" : ""
    readonly property bool emptySubmit: keyMode === "fido2"

    // what to show (Settings → Login screen; settings.json is the shell's copy)
    readonly property var show: LockItems.resolveGreeter(Settings.lockscreen, Settings.greeter)
    // { owner, yubikey, yubikeyMode, face } written by the shell
    readonly property var meta: { try { return JSON.parse(metaFile.text()) } catch (e) { return {} } }
    FileView { id: metaFile; path: root.dataDir + "/meta.json"; blockLoading: true; printErrors: false }
    readonly property string wallpaper: dataDir + "/wallpaper.jpg"
    readonly property string hostname: Files.read("/etc/hostname").trim()

    // ── Users and sessions ──
    readonly property var users: GreeterLib.users(Files.read("/etc/passwd"))
    property var user: null                 // { name, uid, gecos }
    readonly property bool isOwner: user !== null && user.name === meta.owner
    // the owner's display name / picture come from the shell; other users get their name
    readonly property string displayName: isOwner && Settings.profile.name ? Settings.profile.name : (user?.gecos || user?.name || "")
    readonly property string avatar: isOwner && meta.face === true ? dataDir + "/face.png" : ""
    readonly property bool userPicker: show.userPicker === "on" || (show.userPicker === "auto" && users.length > 1)

    property var sessions: []               // [{ id, name, exec, desktopNames, tryExec }]
    property var session: null
    FolderListModel {
        id: sessionDir
        folder: "file:///usr/share/wayland-sessions"
        nameFilters: ["*.desktop"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) root.loadSessions()
    }
    function loadSessions() {
        const list = []
        for (let i = 0; i < sessionDir.count; i++) {
            const file = sessionDir.get(i, "fileName")
            const s = GreeterLib.parseDesktop(file.replace(/\.desktop$/, ""), Files.read("/usr/share/wayland-sessions/" + file))
            if (s) list.push(s)
        }
        // TryExec: drop sessions whose program isn't installed
        const tries = list.map(s => s.tryExec).filter(t => t !== "")
        if (tries.length === 0) return setSessions(list)
        tryExec.found = []
        tryExec.list = list
        tryExec.command = ["sh", "-c", 'for t; do command -v -- "$t" >/dev/null 2>&1 && printf "%s\\n" "$t"; done', "sh"].concat(tries)
        tryExec.running = true
    }
    function setSessions(list) {
        sessions = list.sort((a, b) => a.name.localeCompare(b.name))
        pickDefaults()
    }
    Process {
        id: tryExec
        property var list: []
        property var found: []
        stdout: SplitParser { onRead: line => tryExec.found.push(line) }
        onExited: root.setSessions(list.filter(s => s.tryExec === "" || found.includes(s.tryExec)))
    }

    // last user / session (state dir), else the settings' defaults, else the owner / first
    FileView { id: lastFile; path: root.stateDir + "/last.json"; blockLoading: true; blockWrites: true; printErrors: false }
    function pickDefaults() {
        let last = {}
        try { last = JSON.parse(lastFile.text()) } catch (e) {}
        if (!user) user = GreeterLib.pick(users, "name", [show.defaultUser, last.user, meta.owner])
        if (!session) session = GreeterLib.pick(sessions, "id", [show.defaultSession, last.session, "niri"])
    }
    function saveLast() {
        lastFile.setText(JSON.stringify({ user: user?.name ?? "", session: session?.id ?? "" }) + "\n")
    }

    function chooseUser(u) {
        if (checking || unlocking) return
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
        user = u
        password = ""; status = ""; failed = false
    }
    function chooseSession(s) { if (!unlocking) session = s }

    // ── Which monitor shows the UI (as the lockscreen: Settings → Lockscreen) ──
    // outputs as "make model serial" from the compositor (niri; hyprctl for
    // the two-monitor test in a nested Hyprland), fixed commands only
    property var outputs: []                // [{ name, ident }]
    property string focused: ""
    readonly property string mainScreen: {
        const names = Quickshell.screens.map(s => s.name)
        if (show.monitors.length === 0) return ""
        const hit = show.monitors.map(id => outputs.find(o => o.ident === id || o.name === id)).find(o => o && names.includes(o.name))
        if (hit) return hit.name
        return names.includes(focused) ? focused : (names[0] ?? "")
    }
    function showsUi(screenName) { return mainScreen === "" || screenName === mainScreen }
    function ident(o) { return [o.make || "Unknown", o.model || "Unknown", o.serial || "Unknown"].join(" ") }
    Process {
        id: niriOutputs
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    root.outputs = Object.values(j).map(o => ({ name: o.name, ident: root.ident(o) }))
                } catch (e) { hyprOutputs.running = true }
            }
        }
        onExited: code => { if (code !== 0) hyprOutputs.running = true }
    }
    Process {
        id: hyprOutputs
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    root.outputs = j.map(o => ({ name: o.name, ident: root.ident({ make: o.make, model: o.model, serial: o.serial }) }))
                    root.focused = (j.find(o => o.focused) ?? {}).name ?? ""
                } catch (e) {}
            }
        }
    }
    Process {
        id: niriFocused
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector { onStreamFinished: { try { root.focused = JSON.parse(text)?.name ?? "" } catch (e) {} } }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { niriOutputs.running = true }
    }

    // ── Auth (greetd) ──
    property string lastMessage: ""
    property bool answered: false           // the password went to the first prompt
    property bool extraPrompt: false        // PAM asked for more (e.g. an OTP): the next submit answers it

    function showAuth() {
        if (unlocking) return
        authOpen = true
        authIdle.restart()
    }
    function hideAuth() {
        if (checking) return
        if (extraPrompt && Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
        extraPrompt = false
        authOpen = false
        password = ""
        status = ""
        failed = false
    }
    function submit() {
        if (checking || unlocking || (password.length === 0 && !emptySubmit) || !user || !session) return
        failed = false
        checking = true
        status = "Checking…"
        if (extraPrompt) {
            extraPrompt = false
            Greetd.respond(password)
            return
        }
        lastMessage = ""
        answered = false
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
        Greetd.createSession(user.name)
    }
    function fail(msg) {
        checking = false
        extraPrompt = false
        password = ""
        status = msg
        failed = false
        failed = true      // re-trigger the shake
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (!root.answered) {
                    root.answered = true
                    Greetd.respond(root.password)
                } else {
                    // a second question (OTP, …): show it, the next submit answers
                    root.extraPrompt = true
                    root.checking = false
                    root.password = ""
                    root.status = message.trim().replace(/:$/, "")
                }
            } else if (message) {
                root.lastMessage = message
                if (error) root.status = message.trim()
                // pam_u2f's cue after the (empty) password: now it waits for the touch
                else if (/touch/i.test(message)) root.status = "Touch your YubiKey…"
            }
        }
        function onAuthFailure(message) { root.fail(AuthText.failure(root.lastMessage + "\n" + message, false)) }
        function onError(error) {
            console.warn("greetd:", error)
            root.unlocking = false
            root.mark("launched", "")           // greetd refused it: not launched after all
            if (!sessionLock.locked) sessionLock.locked = true
            root.fail(AuthText.error())
        }
        function onReadyToLaunch() {
            root.status = ""
            root.unlocking = true
            root.saveLast()
            launchTimer.restart()
        }
    }

    // let the fade-out play, then hand over to the session
    Timer {
        id: launchTimer
        interval: 350
        onTriggered: {
            const s = root.session
            root.mark("launched", s.exec)
            sessionLock.locked = false
            Greetd.launch(GreeterLib.splitExec(s.exec), GreeterLib.sessionEnv(s), true)
        }
    }

    // back to the clock after 30s without typing
    Timer {
        id: authIdle
        interval: 30000
        onTriggered: if (!root.checking && root.password.length === 0) root.hideAuth()
    }
    onPasswordChanged: if (authOpen) authIdle.restart()

    // ── Power (systemctl as the greeter: logind allows it for the active session) ──
    function power(id) {
        const cmd = { suspend: "suspend", reboot: "reboot", poweroff: "poweroff" }[id]
        if (!cmd) return
        if (dryRun) { console.info("greeter dry run: systemctl " + cmd); mark("power", cmd); return }
        Quickshell.execDetached(["systemctl", cmd])
    }

    // markers for the session wrapper (greeter/system/greeter-session)
    function mark(name, text) {
        if (runDir === "") return
        const f = markerComp.createObject(null, { path: runDir + "/" + name })
        f.setText((text ?? "") + "\n")
        f.destroy()
    }
    Component { id: markerComp; FileView { blockWrites: true; printErrors: false } }

    CapsLock { id: caps; active: sessionLock.locked }

    Component.onCompleted: {
        niriOutputs.running = true
        niriFocused.running = true
        if (!Greetd.available) console.warn("greeter: GREETD_SOCK isn't set, logging in won't work")
        sessionLock.locked = true
    }

    WlSessionLock {
        id: sessionLock
        onSecureChanged: if (secure) root.mark("ready", "")

        WlSessionLockSurface {
            id: surface
            color: "black"
            GreeterSurface {
                anchors.fill: parent
                lock: root
                screen: surface.screen
            }
        }
    }
}
