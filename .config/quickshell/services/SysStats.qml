pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU / memory / temperature / NVIDIA GPU numbers, shared by the bar modules
// (and the performance monitor). Reads /proc and /sys directly; only the GPU
// needs a process (nvidia-smi, if installed).
//
// Polls only while something uses it: call acquire() when a consumer appears
// and release() when it goes away.
//
//   cpu, mem (percent), memUsed / memTotal (KiB), cpuTemp, gpu, gpuTemp
//   -1 = unknown / not available (e.g. no NVIDIA GPU)
Singleton {
    id: root

    property int users: 0
    function acquire() { users++ }
    function release() { users = Math.max(0, users - 1) }

    property int interval: Properties.interval

    property int cpu: -1
    property int mem: -1
    property real memUsed: 0
    property real memTotal: 0
    property int cpuTemp: -1
    property int gpu: -1
    property int gpuTemp: -1
    property bool hasNvidia: false

    property var _prevCpu: null
    property string _tempPath: ""

    Timer {
        running: root.users > 0
        interval: Math.max(250, root.interval)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload(); meminfo.reload()
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
