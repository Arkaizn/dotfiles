import Quickshell
import Quickshell.Io
import QtQuick

// The file manager's backend client: one long-running scripts/files/filesd.py
// (JSON lines; the protocol is in its header), shared by every window.
//
//   request(op, args, { batch: items => …, progress: m => …, ask: m => …, done: res => …, error: (msg, code) => … })  → id
//   cancel(id)                 stops a listing; its error callback gets code "cancelled"
//   ready                      the backend answered; requests sent before wait in a queue
//   problem                    "" or why it isn't running (shown as a Banner)
//   signal event(var m)        changed / gone / places (see the protocol)
//   signal restarted()         back after a crash: watches are gone, re-send them
//
// A crash fails every open request (code "io") and restarts it with backoff
// (0.5, 1, 2, 5, 10 s); 30 s of running resets the backoff.
Scope {
    id: root

    property bool ready: false
    property string problem: ""
    signal event(var m)
    signal restarted()

    property int _next: 1
    property var _pending: ({})          // id → callbacks
    property var _queue: []              // lines written once it's ready
    property int _tries: 0
    property bool _started: false
    readonly property var _backoff: [500, 1000, 2000, 5000, 10000]

    function request(op, args, cb) {
        const id = _next++
        _pending[id] = cb ?? {}
        const line = JSON.stringify({ id: id, op: op, args: args ?? {} }) + "\n"
        if (ready) proc.write(line)
        else _queue.push(line)
        return id
    }
    function cancel(id) {
        if (_pending[id]) request("cancel", { target: id })
    }

    function _line(text) {
        let m
        try { m = JSON.parse(text) } catch (e) { console.warn("filesd: not JSON:", text.slice(0, 200)); return }
        if (m.event !== undefined) {
            if (m.event === "ready") {
                ready = true
                problem = ""
                const q = _queue
                _queue = []
                for (const l of q) proc.write(l)
                if (_started) restarted()
                _started = true
                healthy.restart()
                return
            }
            event(m)
            return
        }
        const cb = _pending[m.id]
        if (!cb) return
        if (m.type === "batch") { if (cb.batch) cb.batch(m.items); return }
        if (m.type === "progress") { if (cb.progress) cb.progress(m); return }
        if (m.type === "ask") { if (cb.ask) cb.ask(m); return }
        delete _pending[m.id]
        if (m.type === "done") { if (cb.done) cb.done(m) }
        else if (cb.error) cb.error(m.error ?? "failed", m.code ?? "io")
        else console.warn("filesd:", m.error)
    }

    Process {
        id: proc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/files/filesd.py"]
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => root._line(data) }
        stderr: SplitParser {
            onRead: data => {
                console.warn("filesd:", data)
                errTail.lines = errTail.lines.concat([data]).slice(-3)
            }
        }
        onExited: code => {
            root.ready = false
            healthy.stop()
            const open = root._pending
            root._pending = ({})
            root._queue = []                 // their callbacks fail below: don't send them later
            for (const id in open) if (open[id].error) open[id].error("The file manager's backend stopped", "io")
            const wait = root._backoff[Math.min(root._tries, root._backoff.length - 1)]
            root._tries++
            root.problem = "The backend stopped (exit " + code + ")" + (errTail.lines.length ? ": " + errTail.lines[errTail.lines.length - 1] : "")
                         + " — restarting…"
            restart.interval = wait
            restart.start()
        }
    }
    QtObject { id: errTail; property var lines: [] }
    Timer { id: restart; onTriggered: proc.running = true }
    Timer { id: healthy; interval: 30000; onTriggered: root._tries = 0 }
}
