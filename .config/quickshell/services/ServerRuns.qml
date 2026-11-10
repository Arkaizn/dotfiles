pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// Scans, health checks and updates of the Servers app: manage-svs.sh --json,
// started detached so a config reload or a shell restart never kills an update
// halfway (it writes its events to <dataDir>/state/runs/<time>-<mode>.jsonl;
// this follows the file with `tail --pid`, and finds a run that's still going
// again after a restart).
//
//   start(mode, servers, opts)   mode: "scan" | "check" | "update" | "command" | "snapshots"
//                                opts: { only: "security" | "os" | "containers" | "", reboot: "none" | "auto", snapshot: "off" | "keep" | "drop",
//                                        snapshotFail: "skip" | "update", then: [modes] }
//                                command:   opts { title, script } (scripts/servers/run-command.sh)
//                                snapshots: opts { ids: ["node:tool:vmid:snapshot"] } (deletes them)
//   scanAll()                    scan, then the health checks (the button and the timer)
//   stop()                       Ctrl-C for the script: running servers finish, nothing new starts
//   abortServer(name)            that server stops at its next safe point (a hanging scan / command is cut off)
//   abortRun()                   an update: every server stops at its next safe point, nothing new starts;
//                                anything else (scan, checks, command): killed
//   killRun()                    kill it now, whatever it does (an update can be left half done)
//   answer(id, label)            answer a question of the script (run.asks: roll back? …)
//   queue                        what starts after the current run: [{ id, mode, servers, opts, auto }]
//                                (start() while busy queues; removeQueued(id); survives reloads)
//   run                          the current / last run: { mode, servers, waves, per: { name:
//                                { phase, status, log, seconds, problems } }, lines, done,
//                                result, exit, report, log, error, started }
//   busy · busyMode · progress (0…1)
//
// Automatic (this device's own preferences, ServerStore.prefs):
//   autoScan (default true): a scan + check 1 min after the shell starts (unless
//   the last one is under 30 min old) and every scanHours (default 6).
//   notify (default true): a notification when a scan finds something critical that
//   wasn't there before (security updates, reboot needed), with Show / Update critical;
//   and when an update finishes.
Singleton {
    id: root

    readonly property string script: ServerStore.script
    readonly property string runsDir: ServerStore.dataDir + "/state/runs"
    readonly property bool autoScan: ServerStore.prefs.autoScan ?? true
    readonly property bool notifyOn: ServerStore.prefs.notify ?? true
    readonly property bool askOnFailure: ServerStore.prefs.askOnFailure ?? true
    readonly property real askMinutes: Math.max(1, Math.min(720, Number(ServerStore.prefs.askMinutes) || 30))
    readonly property real scanHours: Math.max(1, Math.min(168, Number(ServerStore.prefs.scanHours) || 6))

    property var run: null
    property bool busy: false
    readonly property string busyMode: busy && run ? run.mode : ""
    property string lastError: ""
    // finished and everything fine: the panel may go away by itself (RunPanel)
    property bool dismissed: false

    // ── Queue ───────────────────────────────────────────────────────────────
    // [{ id, mode, servers, opts, auto }] — auto: a follow-up this added itself (health checks
    // after a scan, the rescan after an update). Kept across config reloads.
    property var queue: []
    PersistentProperties {
        id: keep
        reloadableId: "serverRunsQueue"
        property string queue: "[]"
    }
    onQueueChanged: keep.queue = JSON.stringify(queue)
    function qitem(mode, servers, opts, auto) {
        return { id: "q" + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36), mode: mode, servers: servers ?? [], opts: opts ?? {}, auto: !!auto }
    }
    function enqueue(mode, servers, opts, auto) { queue = queue.concat([qitem(mode, servers, opts, auto)]) }
    function removeQueued(id) { queue = queue.filter(q => q.id !== id) }
    function clearQueue() { queue = [] }
    // "Update · security only · 3 servers"
    function describe(q) {
        const n = (q.servers ?? []).length
        const who = n === 0 ? "all servers" : n === 1 ? q.servers[0] : n + " servers"
        switch (q.mode) {
        case "scan": return "Scan · " + who
        case "check": return "Health checks · " + who
        case "update": return ({ security: "Security updates · ", os: "Packages · ", containers: "Containers · " }[q.opts?.only ?? ""] ?? "Update · ") + who
        case "command": return "“" + (q.opts?.title || "Command") + "” · " + who
        case "snapshots": return "Delete " + (q.opts?.ids ?? []).length + " snapshots"
        }
        return q.mode
    }
    // after an abort the queue waits: you stopped something for a reason (resume() goes on)
    property bool paused: false
    function resume() { paused = false; startNext() }
    function startNext() {
        if (busy || paused || queue.length === 0) return
        const q = queue[0]
        queue = queue.slice(1)
        start(q.mode, q.servers, q.opts)
    }

    readonly property real progress: {
        if (!run || !run.servers.length) return 0
        const n = run.servers.length
        if (run.mode !== "update") return Object.values(run.per).filter(p => p.status !== "").length / n
        const done = Object.values(run.per).filter(p => p.status !== "").length
        return Math.min(1, done / n)
    }
    function per(name) { return busy && run ? (run.per[name] ?? null) : null }

    // ── Starting ────────────────────────────────────────────────────────────
    readonly property string commandScript: Quickshell.shellDir + "/scripts/servers/run-command.sh"
    // the whole command line of a run
    function argvFor(mode, servers, opts) {
        if (mode === "command")
            return [commandScript, opts.title || "Command", opts.script].concat(servers.map(n => {
                const s = ServerStore.get(n); return n + "|" + ServerStore.destOf(s) + "|" + s.port }))
        if (mode === "snapshots")
            return ServerStore.engine(["snapshots", "--json", "--delete", "--ids", (opts.ids ?? []).join(",")])
        return ServerStore.engine(argsFor(mode, servers, opts))
    }
    function argsFor(mode, servers, opts) {
        const a = mode === "update" ? ["update", "--auto"] : [mode]
        a.push("--json")
        if (mode !== "update") a.push("--no-notify")           // ntfy only for real updates
        if (servers && servers.length) a.push("--servers", servers.join(","))
        if (mode === "update") {
            if (opts?.only) a.push("--only", opts.only)
            // Proxmox snapshots before updating (Settings → Servers, or this run's choice)
            const snap = opts?.snapshot ?? ServerStore.snapshotMode
            if (snap === "off") a.push("--no-snapshot")
            else if (snap === "drop") a.push("--drop-snapshot")
            if (snap !== "off" && (opts?.snapshotFail ?? ServerStore.snapshotFail) === "update") a.push("--snapshot-optional")
            a.push("--reboot", opts?.reboot === "auto" ? "auto" : "none")
            // questions (roll back? without a snapshot? next wave?) come here instead of the
            // svs.conf policy deciding alone; unanswered for askMinutes, the policy applies
            if (askOnFailure) a.push("--ask", "--ask-timeout", String(Math.round(askMinutes * 60)))
        }
        return a
    }

    function start(mode, servers, opts) {
        if (busy) { enqueue(mode, servers, opts, false); return }
        if (!["scan", "check", "update", "command", "snapshots"].includes(mode)) return
        if (mode === "command" && !(opts?.script ?? "").trim()) return
        if (mode === "snapshots" && !(opts?.ids ?? []).length) return
        const asked = servers ?? []
        servers = asked.filter(n => ServerStore.get(n) && !ServerStore.get(n).archived)
        // asked for some servers but none is (still) here: nothing, never "all of them"
        if (asked.length > 0 && servers.length === 0) return
        lastError = ""
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
        const file = runsDir + "/" + stamp + "-" + mode + ".jsonl"
        busy = true
        dismissed = false
        paused = false
        // what it is, for a shell that finds it still running after a reload / restart
        Jobs.runInput(["sh", "-c", 'mkdir -p -- "$(dirname -- "$1")" && cat > "$1.meta"', "sh", file],
                      JSON.stringify({ mode: mode, servers: servers, opts: opts ?? {} }), () => {})
        // (snapshot deletion isn't about servers: no rows)
        reset(file, mode, mode === "snapshots" ? [] : servers.length ? servers : ServerStore.active.map(s => s.name), opts)
        // detached: survives reloads and restarts; the pid file tells a later shell it's still running
        Jobs.run(["mkdir", "-p", runsDir], () => {
            Jobs.detached(["setsid", "bash", "-c", 'echo $$ > "$0.pid"; exec "$@" > "$0" 2> "$0.err"', file].concat(argvFor(mode, servers, opts)), null, ServerStore.dataDir)
            Jobs.later(400, () => follow(file))
        })
        if (mode === "scan") ServerStore.setPref("lastAutoScan", Date.now())
    }

    // scan, then the health checks
    function scanAll(servers) {
        start("scan", servers ?? [], { then: ["check"] })
    }

    function stop() {
        if (!busy || !run) return
        Jobs.run(["sh", "-c", 'p=$(cat -- "$1.pid" 2>/dev/null) && kill -INT "$p"', "sh", run.file])
        log("warn", "Stop asked: the running servers finish, nothing new starts")
    }

    // the run's control folder ("ctl" of its start event): the script looks there for abort.<server>
    function ctlTouch(name) {
        if (!run || !run.ctl || !/^[A-Za-z0-9._-]+$/.test(name)) return false
        Jobs.run(["sh", "-c", ': > "$1/abort.$2"', "sh", run.ctl, name])
        return true
    }
    // one server: stops at its next safe point (never in the middle of a package install);
    // a scan or command that hangs is cut off
    function abortServer(name) {
        if (!busy || !run) return
        if (ctlTouch(name)) {
            setPer(name, { aborting: true })
            log("warn", "Abort asked for " + name + (run.mode === "update" ? ": it stops at its next safe point" : ""), name)
        }
    }
    // the whole run. An update: every server stops at its next safe point and nothing new starts
    // (a package install that is running finishes first). Anything else is read-only: killed.
    function abortRun() {
        if (!busy || !run) return
        if (run.mode === "update" || run.mode === "snapshots") {
            ctlTouch("_all")
            stop()
            mark({ aborting: true })
        } else killRun()
    }
    // now, whatever it does: its whole process group (setsid made it one)
    function killRun() {
        if (!busy || !run) return
        mark({ aborted: true })
        log("error", "Killed by you")
        Jobs.run(["sh", "-c", 'p=$(cat -- "$1.pid" 2>/dev/null) && kill -TERM -- "-$p"', "sh", run.file])
    }
    function mark(fields) { if (run) run = Object.assign({}, run, fields) }

    // a question of the script (run.asks): the chosen option's text goes into its answer file
    function answer(id, label) {
        const a = (run?.asks ?? []).find(x => x.id === id)
        if (!a || !a.options.includes(label)) return
        Jobs.run(["sh", "-c", 'printf "%s" "$2" > "$1.tmp" && mv -- "$1.tmp" "$1"', "sh", a.answer, label])
        mark({ asks: run.asks.map(x => x.id === id ? Object.assign({}, x, { answered: label }) : x) })
    }
    readonly property var asks: busy && run ? (run.asks ?? []).filter(a => !a.answered) : []

    // ── Following a run ─────────────────────────────────────────────────────
    function reset(file, mode, servers, opts) {
        const per = {}
        for (const s of servers) per[s] = { phase: "", status: "", log: "", seconds: 0, problems: [] }
        run = { file: file, mode: mode, servers: servers, waves: [], per: per, lines: [], done: false, result: "",
                exit: -1, report: "", log: "", error: "", started: Date.now(), opts: opts ?? {},
                ctl: "", asks: [], aborting: false, aborted: false }
    }

    // true while a run is read again from its start (after a reload): no notifications for old events
    property bool replaying: false
    function follow(file) {
        tail.file = file
        tail.running = false
        tail.running = true
    }

    Process {
        id: tail
        property string file: ""
        // waits for the pid file, then follows the events until the script exits
        command: ["sh", "-c", 'for i in $(seq 50); do [ -s "$1.pid" ] && break; sleep 0.1; done\n'
                            + 'p=$(cat -- "$1.pid" 2>/dev/null) || exit 1\n'
                            + 'exec tail -n +1 -F --pid="$p" -- "$1" 2>/dev/null', "sh", file]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: root.finished()
    }

    function log(level, text, server) {
        if (!run) return
        const r = Object.assign({}, run)
        r.lines = run.lines.concat([{ level: level, text: text, server: server ?? "", time: Date.now() }]).slice(-400)
        run = r
    }
    function setPer(name, fields) {
        if (!run) return
        const r = Object.assign({}, run)
        r.per = Object.assign({}, run.per)
        r.per[name] = Object.assign({ phase: "", status: "", log: "", seconds: 0, problems: [] }, run.per[name] ?? {}, fields)
        run = r
    }

    function handle(line) {
        let e
        try { e = JSON.parse(line) } catch (x) { return }
        if (!run) return
        switch (e.event) {
        case "start": {
            const r = Object.assign({}, run)
            r.log = e.log ?? ""
            r.ctl = e.ctl ?? ""
            if (Array.isArray(e.servers) && e.servers.length) {
                r.servers = e.servers
                const per = {}
                for (const s of e.servers) per[s] = run.per[s] ?? { phase: "", status: "", log: "", seconds: 0, problems: [] }
                r.per = per
            }
            run = r
            break
        }
        case "plan": { const r = Object.assign({}, run); r.waves = e.waves ?? []; run = r; break }
        case "log": log(e.level, e.text, e.server); break
        case "phase": setPer(e.server, Object.assign({ phase: e.text }, e.log ? { log: e.log } : {})); break
        case "scan":
            setPer(e.server, run.mode === "update" && e.reachable ? { phase: "scanned" } : { phase: "", status: e.reachable ? "ok" : "unreachable",
                   problems: e.reachable ? [] : [e.error ?? "unreachable"] })
            break
        case "check":
            setPer(e.server, { phase: "", status: !e.reachable ? "unreachable" : e.issues.length ? "unhealthy" : "ok", problems: e.issues })
            break
        case "result":
            setPer(e.server, { phase: "", status: e.status, seconds: e.seconds ?? 0, problems: e.problems ?? [], log: e.log ?? "",
                               reboot: e.reboot, packages: (e.packages ?? []).length, containers: (e.containers ?? []).length })
            break
        case "deleted": log(e.ok ? "ok" : "error", (e.ok ? "deleted " : "couldn't delete ") + e.id); break
        case "snapshots": log("info", (e.snapshots ?? []).length + " update snapshots found" + ((e.unreachable ?? []).length ? ", unreachable: " + e.unreachable.join(", ") : "")); break
        case "ask": {
            // the script waits for an answer (ServerRuns.answer); tell the user if the window is closed
            const a = { id: e.id, server: e.server ?? "", question: e.question, detail: e.detail ?? "", options: e.options ?? [],
                        answer: e.answer, timeout: e.timeout ?? 0, time: Date.now(), answered: "" }
            mark({ asks: (run.asks ?? []).filter(x => x.id !== a.id).concat([a]) })
            if (a.server) setPer(a.server, { phase: "waiting for your answer" })
            if (notifyOn && !replaying) notifyDetached(["-a", "Servers", "-u", "critical", "-i", "dialog-question", "-A", "show=Answer",
                                                         (a.server || "Update") + " needs a decision", a.question], [])
            break
        }
        case "asked": mark({ asks: (run.asks ?? []).filter(x => x.id !== e.id) }); break
        case "aborted": setPer(e.server, { phase: "", status: "aborted", problems: [] }); break
        case "error": { const r = Object.assign({}, run); r.error = e.error; run = r; log("error", e.error); break }
        case "done": {
            const r = Object.assign({}, run)
            r.done = true; r.result = e.result ?? ""; r.exit = e.exit ?? -1; r.report = e.report ?? ""; r.log = e.log || r.log
            // an update's servers that had nothing to do never get a result: say so
            if (r.mode === "update") for (const s of r.servers) if (r.per[s] && r.per[s].status === "") r.per[s] = Object.assign({}, r.per[s], { status: "up-to-date", phase: "" })
            run = r
            ServerStore.reloadState()
            break
        }
        }
    }

    // the script ended (or the tail did)
    function finished() {
        if (!run || !busy) return
        busy = false
        if (!run.done) {
            Jobs.run(["sh", "-c", 'tail -n 5 -- "$1.err" 2>/dev/null', "sh", run.file], (c, err) => {
                const r = Object.assign({}, run)
                r.done = true
                r.error = r.aborted ? "killed by you" : r.error || err.trim().split("\n").pop() || "the script ended without a result"
                run = r
                after()
            })
        } else after()
    }

    function after() {
        const r = run
        const cut = r.aborted || r.aborting
        if (r.mode === "scan" && !cut) Qt.callLater(checkCritical)
        let follow = []
        if (r.mode === "update") {
            notifyUpdate(r)
            // every server of the run: scan again for the new state (the script marks them
            // all out of date, also the skipped ones; unreachable ones get their state back too)
            if (r.servers.length && !r.aborted) follow = [qitem("scan", r.servers, { then: ["check"] }, true)]
        }
        // follow-ups (a scan's health checks) on the same servers ([] = all of them); not after an abort
        if (!cut) {
            const same = r.servers.length >= ServerStore.active.length ? [] : r.servers
            follow = (r.opts?.then ?? []).map(m => qitem(m, same, {}, true)).concat(follow)
        }
        if (follow.length) queue = follow.concat(queue)
        Jobs.run(["sh", "-c", 'rm -f -- "$1.pid" "$1.meta"; ls -1t "$2"/*.jsonl 2>/dev/null | tail -n +31 | while read -r f; do rm -f -- "$f" "$f.err" "$f.pid" "$f.meta"; done', "sh", r.file, runsDir])
        if (cut && queue.length) paused = true
        else if (queue.length) Jobs.later(500, startNext)
        // everything fine and nothing waiting: the panel goes away by itself after a moment
        else if (fine(r)) Jobs.later(6000, () => { if (!busy && run === r) dismissed = true })
    }
    // the servers of the last update that didn't go through (the panel's Retry)
    readonly property var retryable: !busy && run && run.mode === "update"
        ? run.servers.filter(s => ["failed", "skipped", "aborted", "unreachable"].includes(run.per[s]?.status)) : []

    // nothing in it that the user needs to look at
    function fine(r) {
        if (!r || r.error || r.aborted || r.aborting || r.result === "FAILED" || r.result === "ATTENTION") return false
        return !Object.values(r.per).some(p => ["failed", "needs-look", "unreachable", "unhealthy", "rolled-back", "aborted", "skipped"].includes(p.status))
    }

    // ── Notifications ───────────────────────────────────────────────────────
    // detached, so a reload doesn't kill notify-send while it waits for a click (the
    // notification and its buttons would go with it); a click comes back over IPC:
    //   show → servers open · update → servers confirmUpdate security <servers>
    function notifyDetached(args, servers) {
        Jobs.detached(["bash", "-c", 'a=$(notify-send "${@:2}")\n'
                     + 'case "$a" in show) qs ipc call servers open ;; update) qs ipc call servers confirmUpdate security "$1" ;; esac',
                     "bash", (servers ?? []).join(",")].concat(args), null)
    }

    // critical = security updates and "reboot needed"; only what wasn't there at the last scan
    function checkCritical() {
        const seen = ServerStore.prefs.seenCritical ?? {}
        const now = {}, fresh = []
        for (const s of ServerStore.active) {
            const sc = ServerStore.scans[s.name]
            if (!sc || !sc.reachable) { if (seen[s.name]) now[s.name] = seen[s.name]; continue }
            const items = (sc.packages ?? []).filter(p => p.security).map(p => p.name).concat(sc.reboot ? ["(reboot)"] : [])
            now[s.name] = items
            const old = seen[s.name] ?? []
            if (items.some(i => !old.includes(i))) fresh.push({ name: s.name, sec: items.filter(i => i !== "(reboot)").length, reboot: sc.reboot })
        }
        ServerStore.setPref("seenCritical", now)
        if (!notifyOn || fresh.length === 0) return
        const body = fresh.slice(0, 6).map(f => f.name + ": " + [f.sec ? f.sec + " security" : "", f.reboot ? "reboot needed" : ""].filter(x => x).join(", ")).join("\n")
                     + (fresh.length > 6 ? "\n…" : "")
        // "Update critical" never starts anything: the window opens with the confirmation
        notifyDetached(["-a", "Servers", "-u", "critical", "-i", "security-high", "-A", "update=Update critical", "-A", "show=Show",
                        fresh.length === 1 ? "Critical update on " + fresh[0].name : "Critical updates on " + fresh.length + " servers", body],
                       fresh.filter(f => f.sec > 0).map(f => f.name))
    }

    function notifyUpdate(r) {
        if (!notifyOn) return
        const st = r.servers.map(s => r.per[s]?.status ?? "")
        const n = k => st.filter(x => x === k).length
        const failed = n("failed") + n("unreachable"), ok = n("ok"), rolled = n("rolled-back"), cut = n("aborted"), skipped = n("skipped")
        const reboots = r.servers.filter(s => ["pending", "manual"].includes(r.per[s]?.reboot))
        const body = [ok ? ok + " updated" : "", failed ? failed + " failed" : "", rolled ? rolled + " rolled back" : "",
                      cut ? cut + " aborted" : "", skipped ? skipped + " skipped" : "",
                      reboots.length ? "reboot by hand: " + reboots.join(", ") : "", r.error].filter(x => x).join("\n")
        notifyDetached(["-a", "Servers", "-i", failed || r.error ? "dialog-warning" : "system-software-update",
                        "-A", "show=Show", (r.opts?.only === "security" ? "Security updates " : "Updates ") + (failed || r.error ? "finished with problems" : "done"),
                        body || "Nothing to do"], [])
    }

    // ── Automatic scans ─────────────────────────────────────────────────────
    function autoTick() {
        if (!autoScan || busy || !ServerStore.exists || ServerStore.active.length === 0) return
        const last = Math.max(ServerStore.lastScan, Number(ServerStore.prefs.lastAutoScan) || 0)
        if (Date.now() - last >= scanHours * 3600000) scanAll()
    }
    // at shell start: unless the last scan is under 30 min old (reloads don't rescan)
    Timer {
        interval: 60000
        running: true
        onTriggered: {
            const last = Math.max(ServerStore.lastScan, Number(ServerStore.prefs.lastAutoScan) || 0)
            if (root.autoScan && !root.busy && ServerStore.exists && Date.now() - last > 30 * 60000) root.scanAll()
        }
    }
    Timer { interval: 5 * 60000; repeat: true; running: true; onTriggered: root.autoTick() }

    // a run still going from before a reload / restart: follow it again (what it is: its .meta);
    // nothing running but something queued (it ended while the shell was reloading): go on
    Component.onCompleted: {
        try { queue = JSON.parse(keep.queue) } catch (e) { queue = [] }
        Jobs.run(["sh", "-c", 'for f in $(ls -1t "$1"/*.jsonl.pid 2>/dev/null); do p=$(cat -- "$f"); kill -0 "$p" 2>/dev/null && { printf "%s\\n" "${f%.pid}"; cat -- "${f%.pid}.meta" 2>/dev/null; exit; }; done', "sh", runsDir], (c, out) => {
            const lines = out.split("\n")
            const file = lines[0].trim()
            if (!file) { if (queue.length) Jobs.later(1500, startNext); return }
            let meta = {}
            try { meta = JSON.parse(lines.slice(1).join("\n")) } catch (e) {}
            const m = /-(scan|check|update|command|snapshots)\.jsonl$/.exec(file)
            busy = true
            replaying = true
            Jobs.later(3000, () => replaying = false)
            reset(file, meta.mode ?? (m ? m[1] : "scan"), meta.servers?.length ? meta.servers : ServerStore.active.map(s => s.name), meta.opts ?? {})
            follow(file)
        })
    }

    IpcHandler {
        target: "serverRuns"
        function scan(): void { root.scanAll() }
        function status(): string {
            if (!root.run) return "idle"
            return (root.busy ? "running " : "last ") + root.run.mode + ": " + root.run.servers.map(s => s + "=" + (root.run.per[s]?.status || root.run.per[s]?.phase || "…")).join(" ")
                   + (root.run.error ? " · " + root.run.error : "")
        }
        function stop(): void { root.stop() }
        function abort(): void { root.abortRun() }
        // a shell snippet on servers (comma separated names), like the app's "Run command"
        function command(title: string, script: string, servers: string): void {
            root.start("command", servers.split(",").filter(x => x !== ""), { title: title, script: script })
        }
        // the open questions ("id<TAB>question<TAB>option | option"), and answering one with an option's text
        function asks(): string { return root.asks.map(a => a.id + "\t" + a.question + "\t" + a.options.join(" | ")).join("\n") }
        function answer(id: string, label: string): void { root.answer(id, label) }
        function abortServer(name: string): void { root.abortServer(name) }
        function queue(): string { return root.queue.map(q => root.describe(q) + (q.auto ? " (auto)" : "")).join("\n") }
        // notify again about everything critical right now (forgets what was already seen)
        function remind(): void { ServerStore.setPref("seenCritical", {}); root.checkCritical() }
    }
}
