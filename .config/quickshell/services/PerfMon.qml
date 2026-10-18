pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Data for the performance monitor window (modules/perfmon). Runs only while
// `active` (the window is open): one streamed shell loop for /proc + /sys and
// nvidia-smi's own loop mode, both stopped when the window closes.
//
// All hwmon temperatures / fans are found by themselves (label "chip · name");
// a liquid cooler (kraken*, NZXT) gives the coolant / pump / fan values.
//
//   qs ipc call perfmon toggle
Singleton {
    id: root

    property bool active: false
    signal toggleRequested()
    readonly property int interval: Math.max(500, Math.min(5000, Settings.perfmon.interval ?? 1000))
    readonly property int historyLength: 90

    // ── current values (-1 = unknown) ───────────────────────────────────────
    property real cpu: -1
    property var cores: []                  // % per core
    property real cpuFreq: -1               // MHz (average)
    property real cpuTemp: -1
    property real memUsed: 0                // KiB
    property real memTotal: 0
    property real swapUsed: 0
    property real swapTotal: 0
    readonly property real mem: memTotal > 0 ? 100 * memUsed / memTotal : -1
    property real netRx: 0                  // bytes / s
    property real netTx: 0
    property var sensors: []                // [{ path, chip, label, kind: "temp" | "fan", value }]
    // the ones with a reading (a 0 °C temp = sensor not connected)
    readonly property var shownSensors: sensors.filter(s => s.value >= 0 && !(s.kind === "temp" && s.value === 0))
    property var disks: []                  // [{ mount, used, size }]
    property var procs: []                  // [{ pid, name, cpu, mem }]

    property bool hasGpu: false
    property var gpu: ({})                  // { name, util, temp, memUsed, memTotal, power, powerLimit, clock, fan }

    readonly property var cooler: {
        const k = sensors.filter(s => /^kraken|^nzxt/i.test(s.chip))
        return k.length === 0 ? null : {
            coolant: k.find(s => s.kind === "temp")?.value ?? -1,
            pump: k.find(s => s.kind === "fan" && /pump/i.test(s.label))?.value ?? -1,
            fan: k.find(s => s.kind === "fan" && !/pump/i.test(s.label))?.value ?? -1
        }
    }

    // ── history (oldest first) ──────────────────────────────────────────────
    property var hist: ({ cpu: [], gpu: [], mem: [], cpuTemp: [], gpuTemp: [], coolant: [], rx: [], tx: [] })
    function push(key, v) {
        const h = Object.assign({}, hist)
        h[key] = h[key].concat([v]).slice(-historyLength)
        hist = h
    }

    onActiveChanged: active ? start() : stop()
    // nvidia-smi and the loop take the interval at start
    onIntervalChanged: if (active) { stop(); start() }

    function start() {
        // the sensor files, once: "S <path> <chip> <label> <kind>"
        Jobs.run(["sh", "-c",
                  'for h in /sys/class/hwmon/hwmon*; do n=$(cat "$h/name" 2>/dev/null)\n'
                + '  for f in "$h"/temp*_input "$h"/fan*_input; do [ -f "$f" ] || continue\n'
                + '    l=$(cat "${f%_input}_label" 2>/dev/null); k=temp; case $f in *fan*) k=fan ;; esac\n'
                + '    printf "S\\t%s\\t%s\\t%s\\t%s\\n" "$f" "$n" "$l" "$k"; done; done'], (code, out) => {
            const list = []
            for (const l of out.split("\n")) {
                const p = l.split("\t")
                if (p[0] !== "S" || p.length < 5) continue
                list.push({ path: p[1], chip: p[2], label: p[3] || p[1].replace(/.*\//, "").replace("_input", ""), kind: p[4], value: -1 })
            }
            sensors = list
            if (!active) return
            startLoop()
        })
        Jobs.which(["nvidia-smi"], h => {
            hasGpu = h["nvidia-smi"]
            if (hasGpu && active)
                Jobs.start("perfmon-gpu", ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,power.limit,clocks.gr,fan.speed",
                                           "--format=csv,noheader,nounits", "-lms", String(interval)], { store: false, onLine: gpuLine })
        })
        tick.start()
    }

    function stop() {
        Jobs.cancel("perfmon-sys")
        Jobs.cancel("perfmon-gpu")
        tick.stop()
        prevCpu = null; prevNet = null
    }

    // one loop: sensors, /proc/stat, meminfo, net, cpu frequency; "E" ends a sample
    function startLoop() {
        const paths = sensors.map(s => s.path)
        Jobs.start("perfmon-sys", ["sh", "-c",
              'iv=$1; shift\n'
            + 'while :; do\n'
            + '  for f in "$@"; do printf "T %s %s\\n" "$f" "$(cat "$f" 2>/dev/null)"; done\n'
            + '  grep "^cpu" /proc/stat\n'
            + '  grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):" /proc/meminfo\n'
            // physical traffic only: virtual interfaces would count it twice
            + '  sed "s/:/ /" /proc/net/dev | awk "NR>2 && \\$1 !~ /^(lo|docker|veth|br-|virbr|tailscale|wg|tun|vmnet|vboxnet)/ {rx+=\\$2; tx+=\\$10} END {print \\"NET\\", rx+0, tx+0}"\n'
            + '  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | awk "{s+=\\$1; n++} END {if (n) printf \\"FREQ %d\\\\n\\", s/n}"\n'
            + '  echo E\n'
            + '  sleep "$iv"\n'
            + 'done', "sh", String(interval / 1000)].concat(paths), { store: false, onLine: sysLine })
    }

    // ── parsing ─────────────────────────────────────────────────────────────
    property var cur: ({})
    property var prevCpu: null
    property var prevNet: null
    property real prevNetTime: 0

    function sysLine(text) {
        let m
        if ((m = /^T (\S+) (-?\d+)$/.exec(text))) { cur.t = cur.t ?? {}; cur.t[m[1]] = Number(m[2]); return }
        if ((m = /^(cpu\d*) (.*)$/.exec(text))) { cur.cpu = cur.cpu ?? {}; cur.cpu[m[1]] = m[2].trim().split(/\s+/).map(Number); return }
        if ((m = /^(\w+):\s+(\d+)/.exec(text))) { cur.mem = cur.mem ?? {}; cur.mem[m[1]] = Number(m[2]); return }
        if ((m = /^NET (\d+) (\d+)$/.exec(text))) { cur.net = [Number(m[1]), Number(m[2])]; return }
        if ((m = /^FREQ ([\d.]+)$/.exec(text))) { cpuFreq = Math.round(Number(m[1]) / 1000); return }
        if (text === "E") { commit(cur); cur = {} }
    }

    function commit(c) {
        // sensors (millidegrees / rpm)
        if (c.t) sensors = sensors.map(s => Object.assign({}, s, { value: c.t[s.path] === undefined ? s.value : (s.kind === "temp" ? c.t[s.path] / 1000 : c.t[s.path]) }))
        const ct = sensors.find(s => /k10temp|coretemp|zenpower/.test(s.chip) && s.kind === "temp")
        cpuTemp = ct ? ct.value : -1
        // cpu % (total and per core) from the jiffies difference
        if (c.cpu) {
            const busy = a => { const idle = a[3] + (a[4] || 0), total = a.reduce((x, y) => x + y, 0); return { idle: idle, total: total } }
            const now = {}
            for (const k in c.cpu) now[k] = busy(c.cpu[k])
            if (prevCpu) {
                const pct = k => { const d = now[k].total - (prevCpu[k]?.total ?? 0); return d > 0 ? 100 * (1 - (now[k].idle - prevCpu[k].idle) / d) : 0 }
                cpu = Math.round(pct("cpu"))
                cores = Object.keys(now).filter(k => k !== "cpu").sort((a, b) => Number(a.slice(3)) - Number(b.slice(3))).map(k => Math.round(pct(k)))
            }
            prevCpu = now
        }
        if (c.mem) {
            memTotal = c.mem.MemTotal ?? 0
            memUsed = memTotal - (c.mem.MemAvailable ?? 0)
            swapTotal = c.mem.SwapTotal ?? 0
            swapUsed = swapTotal - (c.mem.SwapFree ?? 0)
        }
        if (c.net) {
            const t = Date.now()
            if (prevNet && t > prevNetTime) {
                netRx = Math.max(0, (c.net[0] - prevNet[0]) * 1000 / (t - prevNetTime))
                netTx = Math.max(0, (c.net[1] - prevNet[1]) * 1000 / (t - prevNetTime))
            }
            prevNet = c.net; prevNetTime = t
        }
        push("cpu", Math.max(0, cpu)); push("mem", Math.max(0, mem)); push("cpuTemp", cpuTemp)
        push("coolant", cooler?.coolant ?? -1); push("rx", netRx); push("tx", netTx)
        if (hasGpu) { push("gpu", gpu.util ?? 0); push("gpuTemp", gpu.temp ?? -1) }
    }

    function gpuLine(text) {
        const p = text.split(",").map(s => s.trim())
        if (p.length < 9) return
        const n = i => { const v = parseFloat(p[i]); return isNaN(v) ? -1 : v }
        gpu = { name: p[0], util: n(1), temp: n(2), memUsed: n(3), memTotal: n(4), power: n(5), powerLimit: n(6), clock: n(7), fan: n(8) }
    }

    // slower things: top processes (2 s) and disks (10 s)
    property int ticks: 0
    Timer {
        id: tick
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // top's second sample = CPU over the last 0.5 s (ps would give the lifetime average);
            // % of one core → % of the whole machine
            Jobs.run(["top", "-b", "-n", "2", "-d", "0.5", "-o", "%CPU", "-w", "512"], (code, out) => {
                const lines = out.split("\n")
                const hdr = lines.reduce((a, l, i) => /^\s*PID\s/.test(l) ? a.concat([i]) : a, [])
                const threads = Math.max(1, root.cores.length)
                root.procs = lines.slice((hdr[1] ?? lines.length) + 1).map(l => l.trim().split(/\s+/)).filter(f => f.length >= 12)
                    .slice(0, 8).map(f => ({ pid: Number(f[0]), name: f.slice(11).join(" "), cpu: Number(f[8].replace(",", ".")) / threads, mem: Number(f[9].replace(",", ".")) }))
            }, { LC_ALL: "C" })
            if (root.ticks++ % 5 === 0)
                Jobs.run(["df", "-B1", "--output=source,target,used,size", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay"], (code, out) => {
                    const seen = {}, d = []
                    for (const l of out.split("\n").slice(1)) {
                        const m = /^(\S+)\s+(\S+)\s+(\d+)\s+(\d+)$/.exec(l.trim())
                        if (!m || seen[m[1]] || !m[1].startsWith("/dev/")) continue
                        seen[m[1]] = true
                        d.push({ mount: m[2], used: Number(m[3]), size: Number(m[4]) })
                    }
                    root.disks = d
                })
        }
    }

    function bytes(b) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
    }

    IpcHandler {
        target: "perfmon"
        function toggle(): void { root.toggleRequested() }
    }
}
