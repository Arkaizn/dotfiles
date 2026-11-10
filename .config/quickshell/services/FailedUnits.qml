pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Failed systemd units, system and user (systemctl --failed): the list for
// Settings → Maintenance → Failed services, restarting them, and a
// notification when something fails.
//
//   units        [{ name, desc, user, log: [] }]
//   refresh()    read the list again (logs come in afterwards)
//   act(u, "restart" | "reset-failed")
//   restartAll() every failed unit: user ones directly, system ones in one
//                `pkexec systemctl restart` (one password prompt)
//
// Notification (Settings.health.failedNotify, default on): 30 s after the
// shell starts, then every 5 minutes, for units that weren't failed the last
// time it looked, with "Restart all" / "Show" buttons. A unit that recovers
// and fails again notifies again. Remembered across config reloads, so
// editing the config doesn't repeat it.
Singleton {
    id: root

    property var units: []
    property bool loading: false
    property bool busy: false
    property string message: ""

    readonly property bool notify: Settings.health.failedNotify ?? true

    function valid(u) { return /^[A-Za-z0-9@._:\\-]+\.(service|socket|timer|mount|automount|path|target|scope|slice|swap)$/.test(u) }
    function key(u) { return (u.user ? "user:" : "system:") + u.name }

    // cb(units) once both lists are in
    function refresh(cb) {
        loading = true
        const list = []
        let pending = 2
        const done = () => {
            if (--pending > 0) return
            units = list
            loading = false
            for (const u of list) loadLog(u)
            if (cb) cb(list)
        }
        for (const user of [false, true])
            Jobs.run(["systemctl"].concat(user ? ["--user"] : []).concat(["--failed", "--no-legend", "--plain", "--no-pager"]), (code, out) => {
                for (const l of out.split("\n")) {
                    const m = /^(\S+)\s+\S+\s+\S+\s+\S+\s+(.*)$/.exec(l.trim())
                    if (m && valid(m[1])) list.push({ name: m[1], desc: m[2], user: user, log: [] })
                }
                done()
            })
    }

    function loadLog(u) {
        Jobs.run(["journalctl"].concat(u.user ? ["--user-unit"] : ["-u"]).concat([u.name, "-n", "12", "--no-pager", "-o", "short-iso", "-b"]), (code, out) => {
            units = units.map(x => x.name === u.name && x.user === u.user ? Object.assign({}, x, { log: out.split("\n").filter(l => l.trim() && !l.startsWith("-- ")) }) : x)
        })
    }

    function cancelled(code) { return code === 126 || code === 127 }

    function act(u, verb) {
        if (!valid(u.name) || !["restart", "reset-failed"].includes(verb)) return
        const argv = u.user ? ["systemctl", "--user", verb, "--", u.name] : ["pkexec", "systemctl", verb, "--", u.name]
        message = (verb === "restart" ? "Restarting " : "Clearing ") + u.name + "…"
        Jobs.run(argv, (code, out, err) => {
            message = code === 0 ? u.name + (verb === "restart" ? " restarted" : ": failed mark cleared")
                    : cancelled(code) && !u.user ? "cancelled (no password given)" : u.name + ": " + (err.trim().split("\n").pop() || "exit " + code)
            refresh()
        })
    }

    // done(text) when finished; the list is read again a moment later, so
    // a unit that fails right after starting shows up as still failed
    function restartAll(done) {
        if (busy) return
        const go = list => {
            const user = list.filter(u => u.user).map(u => u.name)
            const system = list.filter(u => !u.user).map(u => u.name)
            if (user.length + system.length === 0) { message = "Nothing failed"; if (done) done(message); return }
            busy = true
            message = "Restarting " + (user.length + system.length) + " units…"
            let wasCancelled = false
            const finish = () => {
                settle.callback = () => refresh(after => {
                    busy = false
                    const tried = new Set(list.map(key))
                    const still = after.filter(u => tried.has(key(u)))
                    const ok = list.length - still.length
                    message = (wasCancelled ? "System units: cancelled (no password given). " : "")
                            + ok + " of " + list.length + " restarted"
                            + (still.length ? "; still failed: " + still.map(u => u.name).join(", ") : "")
                    if (done) done(message)
                })
                settle.restart()
            }
            const runSystem = () => {
                if (system.length === 0) return finish()
                // one systemctl call, so one password prompt; it restarts the
                // others even when one of them fails again
                Jobs.run(["pkexec", "systemctl", "restart", "--"].concat(system), code => {
                    wasCancelled = cancelled(code)
                    finish()
                })
            }
            if (user.length === 0) runSystem()
            else Jobs.run(["systemctl", "--user", "restart", "--"].concat(user), () => runSystem())
        }
        // always from a fresh list, so it never restarts something that's fine now
        refresh(list => go(list.filter(u => valid(u.name))))
    }
    Timer { id: settle; interval: 2500; property var callback: null; onTriggered: if (callback) callback() }

    // ── Notification ────────────────────────────────────────────────────────
    PersistentProperties {
        id: persist
        reloadableId: "failedUnits"
        property string seen: "[]"          // keys of the failed units at the last check
        property bool started: false        // the startup check ran (this shell process)
    }

    function check() {
        refresh(list => {
            const before = JSON.parse(persist.seen)
            const now = list.map(key)
            persist.seen = JSON.stringify(now)
            const fresh = list.filter(u => !before.includes(key(u)))
            if (notify && fresh.length > 0) notifyFailed(fresh, list.length)
        })
    }

    function notifyFailed(fresh, total) {
        const names = fresh.slice(0, 6).map(u => u.name + (u.user ? " (user)" : "")).join("\n") + (fresh.length > 6 ? "\n…" : "")
        Jobs.run(["notify-send", "-a", "Services", "-u", "critical", "-i", "dialog-warning",
                  "-A", "restart=Restart all", "-A", "show=Show",
                  total === 1 ? "A service failed" : total + " services failed", names], (code, out) => {
            const a = out.trim()
            if (a === "show") Panels.call("settings", "openPage", "services")
            else if (a === "restart") restartAll(text => {
                Jobs.run(["notify-send", "-a", "Services", "-i", "view-refresh", "Restart all", text])
            })
        })
    }

    Timer {
        id: startupCheck
        running: Settings.loaded && !persist.started
        interval: 30000
        onTriggered: { persist.started = true; root.check() }
    }
    Timer {
        running: persist.started && root.notify
        interval: 5 * 60 * 1000
        repeat: true
        onTriggered: root.check()
    }

    IpcHandler {
        target: "failedUnits"
        function list(): string { return root.units.map(u => (u.user ? "user " : "system ") + u.name).join("\n") }
        function check(): void { root.check() }
        function restartAll(): string { root.restartAll(); return "started" }
        function status(): string { return root.message }
    }
}
