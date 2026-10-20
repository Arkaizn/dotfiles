pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU / memory / temperature / NVIDIA GPU / network numbers, shared by the bar
// modules and the dashboard. Reads /proc and /sys directly; only the GPU needs
// a process (nvidia-smi, if installed).
//
// Polls only while something uses it: call acquire(ms) when a consumer appears
// and release(ms) with the same ms when it goes away; it polls at the shortest
// interval asked for (ms left out = the bar's "Stats refresh").
//
//   cpu, mem (percent), memUsed / memTotal (KiB), cpuTemp, gpu, gpuTemp
//   -1 = unknown / not available (e.g. no NVIDIA GPU)
//   rxRate / txRate: bytes per second over all interfaces (/proc/net/dev)
Singleton {
    id: root

    property var _intervals: []            // one entry per user
    readonly property int users: _intervals.length
    function acquire(ms) { _intervals = _intervals.concat([ms ?? 0]) }
    function release(ms) {
        const i = _intervals.indexOf(ms ?? 0)
        if (i >= 0) _intervals = _intervals.filter((_, k) => k !== i)
    }

    // 0 in the list = the bar's setting
    readonly property int interval: users === 0 ? Properties.interval
                                  : Math.min(..._intervals.map(ms => ms > 0 ? ms : Properties.interval))

    property int cpu: -1
    property int mem: -1
    property real memUsed: 0
    property real memTotal: 0
    property int cpuTemp: -1
    property int gpu: -1
    property int gpuTemp: -1
    property bool hasNvidia: false
    property real rxRate: 0
    property real txRate: 0

    property var _prevCpu: null
    property var _prevNet: null
    property string _tempPath: ""

    Timer {
        running: root.users > 0
        onRunningChanged: if (!running) { root._prevCpu = null; root._prevNet = null }
        interval: Math.max(250, root.interval)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload(); meminfo.reload(); netdev.reload()
            if (root._tempPath !== "") temp.reload()
            if (root.hasNvidia && !smi.running) smi.running = true
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        blockLoading: true
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
            const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0)
            const p = root._prevCpu
            if (p && total > p.total) root.cpu = Math.round(100 * (1 - (idle - p.idle) / (total - p.total)))
            root._prevCpu = { idle: idle, total: total }
            // first reading after a pause: a second one soon, so cpu / net rates don't wait a whole interval
            if (!p) Jobs.later(250, () => { stat.reload(); netdev.reload() })
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        blockLoading: true
        onLoaded: {
            const t = text()
            const total = Number(/MemTotal:\s+(\d+)/.exec(t)?.[1] ?? 0)
            const avail = Number(/MemAvailable:\s+(\d+)/.exec(t)?.[1] ?? 0)
            if (total > 0) {
                root.memTotal = total
                root.memUsed = total - avail
                root.mem = Math.round(100 * (total - avail) / total)
            }
        }
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        blockLoading: true
        onLoaded: root._netSample(text())
    }
    function _netSample(t) {
        // "  eth0: rxBytes … (8 rx fields) txBytes …", after two header lines
        const rows = t.split("\n").slice(2).map(l => l.trim().split(/[:\s]+/)).filter(f => f.length > 9)
        const rx = rows.reduce((a, f) => a + Number(f[1]), 0)
        const tx = rows.reduce((a, f) => a + Number(f[9]), 0)
        const now = Date.now(), p = _prevNet
        if (p && now > p.t) {
            rxRate = Math.max(0, (rx - p.rx) * 1000 / (now - p.t))
            txRate = Math.max(0, (tx - p.tx) * 1000 / (now - p.t))
        }
        _prevNet = { rx: rx, tx: tx, t: now }
    }

    // CPU package temperature: k10temp (AMD) / coretemp (Intel) / zenpower
    FileView {
        id: temp
        path: root._tempPath
        blockLoading: true
        onLoaded: { const v = parseInt(text()); if (!isNaN(v)) root.cpuTemp = Math.round(v / 1000) }
    }
    Process {
        running: true
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do n=$(cat "$h/name" 2>/dev/null); case "$n" in k10temp|coretemp|zenpower) echo "$h/temp1_input"; exit;; esac; done']
        stdout: StdioCollector { onStreamFinished: root._tempPath = text.trim() }
    }

    Process {
        id: smiCheck
        running: true
        command: ["sh", "-c", "command -v nvidia-smi"]
        onExited: code => root.hasNvidia = code === 0
    }
    Process {
        id: smi
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.split("\n")[0].split(",").map(s => parseInt(s))
                root.gpu = isNaN(v[0]) ? -1 : v[0]
                root.gpuTemp = isNaN(v[1]) ? -1 : v[1]
            }
        }
    }
}
