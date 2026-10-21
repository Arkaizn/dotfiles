import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// TEMPORARY: how long a login takes to lock (QS_LOCK_TIMING=1, set in niri's
// startup.kdl). Appends one block per login to ~/.cache/lock-timing.log.
// All times are seconds since boot (/proc/uptime, 10 ms steps), the same
// clock as systemd's *TimestampMonotonic until the first suspend, so a gap
// is one subtraction. Only the shell's first seconds count (like
// LockScreen.startPending): a later reload logs nothing.
// To remove: this file, the `timing` lines in LockScreen.qml and shell.qml,
// QS_LOCK_TIMING in startup.kdl.
Scope {
    id: root

    // plain JS state, not properties: mark() is called from a binding in
    // shell.qml, and reading + writing properties there is a binding loop
    readonly property var st: ({ on: undefined, marks: [], done: false })

    function uptime() { return parseFloat(Files.read("/proc/uptime")) }
    function processStart() {
        const ticks = Number(Files.read("/proc/self/stat").replace(/^.*\) /, "").split(" ")[19])    // starttime, field 22
        return ticks / 100
    }
    function active() {
        if (st.on === undefined)       // decided on the first mark (bindings may not have run yet)
            st.on = Quickshell.env("QS_LOCK_TIMING") === "1" && uptime() - processStart() < 5
        return st.on && !st.done
    }

    function mark(label) {
        if (!active()) return 0
        if (st.marks.length === 0) st.marks.push([processStart(), "qs process start"])
        st.marks.push([uptime(), label])
        return 0
    }

    // after the lock: collect niri's side, write the block
    function finish() {
        if (!active() || st.marks.length === 0) return
        st.done = true
        const sh = "systemctl --user show niri.service -p ExecMainStartTimestampMonotonic -p ActiveEnterTimestampMonotonic; " +
                   "journalctl -b --user -u niri.service -o short-monotonic --no-pager --grep 'locking session' 2>/dev/null | head -1; " +
                   "cat /proc/sys/kernel/random/boot_id"
        Jobs.run(["sh", "-c", sh], (code, out) => write(out))
    }

    function write(out) {
        const marks = st.marks.slice()
        const prop = name => { const m = out.match(new RegExp(name + "=(\\d+)")); return m && m[1] !== "0" ? Number(m[1]) / 1e6 : NaN }
        const niriStart = prop("ExecMainStartTimestampMonotonic")
        const niriReady = prop("ActiveEnterTimestampMonotonic")
        const j = out.match(/^\[\s*([\d.]+)\].*locking session/m)
        const niriLocked = j ? Number(j[1]) : NaN
        if (!isNaN(niriStart)) marks.push([niriStart, "niri process start"])
        if (!isNaN(niriReady)) marks.push([niriReady, "niri ready (niri.service active) = t0"])
        if (!isNaN(niriLocked)) marks.push([niriLocked, "niri: \"locking session\" (journal)"])
        marks.forEach((m, i) => m.push(i))
        marks.sort((a, b) => a[0] - b[0] || a[2] - b[2])

        const t0 = isNaN(niriReady) ? marks[0][0] : niriReady
        const ms = t => (t - t0 >= 0 ? "+" : "") + Math.round((t - t0) * 1000) + " ms"
        const lines = ["", "== login " + new Date().toISOString() + "  boot " + (out.trim().split("\n").pop() ?? "").slice(0, 8)]
        for (const [t, label] of marks)
            lines.push(t.toFixed(3).padStart(9) + "  " + ms(t).padStart(9) + "  " + label)
        const secure = marks.find(m => m[1].startsWith("lock confirmed"))
        const end = !isNaN(niriLocked) ? niriLocked : secure ? secure[0] : NaN
        lines.push("GAP niri ready -> session locked: " + (isNaN(end) ? "? (no lock seen)" : Math.round((end - t0) * 1000) + " ms"))
        Jobs.run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" >> \"$1\"", "lock-timing",
                  (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/lock-timing.log",
                  lines.join("\n")], () => {})
    }
}
