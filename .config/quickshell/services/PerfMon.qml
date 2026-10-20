pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Data for the performance monitor window (modules/perfmon). Runs only while
// `active` (the window is open): one streamed shell loop for /proc + /sys,
// nvidia-smi's own loop mode, and a process scan of /proc/<pid>/stat; all
// stopped when the window closes.
//
// All hwmon temperatures / fans are found by themselves (label "chip · name");
// a liquid cooler (kraken*, NZXT) gives the coolant / pump / fan values.
//
//   qs ipc call perfmon toggle
Singleton {
    id: root

    property bool active: false
    readonly property int interval: Math.max(500, Math.min(5000, Settings.perfmon.interval ?? 1000))
    readonly property int procInterval: Math.max(1000, Math.min(10000, Settings.perfmon.procInterval ?? 2000))
    // 15 minutes of samples (the longest chart range), whatever the interval
    readonly property int historyLength: Math.ceil(900000 / interval)

    // ── current values (-1 = unknown) ───────────────────────────────────────
    property string cpuName: ""
    property real cpu: -1
    property var cores: []                  // % per core
    property real cpuFreq: -1               // MHz (average)
    property real cpuTemp: -1
    property var loadAvg: []                // 1, 5, 15 min
    property real memUsed: 0                // KiB
    property real memTotal: 0
    property real memFree: 0                // KiB; total - used - free = cache the kernel can give back
    property real swapUsed: 0
    property real swapTotal: 0
    readonly property real mem: memTotal > 0 ? 100 * memUsed / memTotal : -1
    property real netRx: 0                  // bytes / s
    property real netTx: 0
    property var sensors: []                // [{ path, hwmon, chip, label, kind: "temp" | "fan", value }]
    // the ones with a reading (a 0 °C temp = sensor not connected)
    readonly property var shownSensors: sensors.filter(s => s.value >= 0 && !(s.kind === "temp" && s.value === 0))
    readonly property var fans: shownSensors.filter(s => s.kind === "fan")
    property var disks: []                  // [{ device, fs, mount, used, size }]

    // processes: [{ pid, ppid, name, cpu (% of the whole machine, -1 = first scan),
    //               mem (resident bytes), threads, kernel, user, cmd }]
    property var procs: []
    property int threadCount: 0
    // user / command need a `ps` per scan: only while one of their columns is shown
    readonly property bool procExtra: Settings.perfmon.procUser === true || (Settings.perfmon.procCommand ?? true) !== false

    property bool hasGpu: false
    property var gpu: ({})                  // { name, util, temp, memUsed, memTotal, power, powerLimit, clock, memClock, fan }
    property real gpuTime: 0
    // nvidia-smi still sending (it can die, e.g. after a driver update)
    property bool gpuValid: false

    readonly property var cooler: {
        const k = sensors.filter(s => /^kraken|^nzxt/i.test(s.chip))
        return k.length === 0 ? null : {
            coolant: k.find(s => s.kind === "temp")?.value ?? -1,
            pump: k.find(s => s.kind === "fan" && /pump/i.test(s.label))?.value ?? -1,
            fan: k.find(s => s.kind === "fan" && !/pump/i.test(s.label))?.value ?? -1
        }
    }

    // ── history (oldest first, -1 = no reading) ─────────────────────────────
    readonly property var histKeys: ["cpu", "gpu", "mem", "cpuTemp", "gpuTemp", "coolant", "rx", "tx"]
    property var hist: emptyHist()
    function emptyHist() { const h = {}; for (const k of histKeys) h[k] = []; return h }
    // all series at once: one change signal per sample
    function pushAll(v) {
        const h = {}
        for (const k of histKeys) {
            const a = hist[k]
            const n = a.length >= historyLength ? a.slice(a.length - historyLength + 1) : a.slice()
            n.push(v[k] ?? -1)
            h[k] = n
        }
        hist = h
    }

    onActiveChanged: active ? start() : stop()
    // nvidia-smi and the loop take the interval at start
    onIntervalChanged: if (active) { stop(); start() }

    function start() {
        hist = emptyHist()
        // the sensor files, once: "S <path> <chip> <label> <kind>"
        Jobs.run(["sh", "-c",
                  'for h in /sys/class/hwmon/hwmon*; do n=$(cat "$h/name" 2>/dev/null)\n'
                + '  for f in "$h"/temp*_input "$h"/fan*_input; do [ -f "$f" ] || continue\n'
                + '    l=$(cat "${f%_input}_label" 2>/dev/null); k=temp; case $f in *fan*) k=fan ;; esac\n'
                + '    printf "S\\t%s\\t%s\\t%s\\t%s\\n" "$f" "$n" "$l" "$k"; done; done\n'
                + 'printf "C\\t%s\\n" "$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2-)"\n'
                + 'printf "P\\t%s\\n" "$(getconf PAGESIZE)"'], (code, out) => {
            const list = []
            for (const l of out.split("\n")) {
                const p = l.split("\t")
                if (p[0] === "C") { cpuName = (p[1] ?? "").trim().replace(/\s+\d+-Core Processor$/, ""); continue }
                if (p[0] === "P") { pageSize = Number(p[1]) || 4096; continue }
                if (p[0] !== "S" || p.length < 5) continue
                list.push({ path: p[1], hwmon: p[1].replace(/\/[^/]*$/, ""), chip: p[2],
                            label: p[3] || p[1].replace(/.*\//, "").replace("_input", ""), kind: p[4], value: -1 })
            }
            sensors = list
            if (!active) return
            startLoop()
        })
        Jobs.which(["nvidia-smi"], h => {
            hasGpu = h["nvidia-smi"]
            if (hasGpu && active)
                Jobs.start("perfmon-gpu", ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,power.limit,clocks.gr,fan.speed,clocks.mem",
                                           "--format=csv,noheader,nounits", "-lms", String(interval)], { store: false, onLine: gpuLine })
        })
        procTimer.start()
        firstRescan.start()
        diskTimer.start()
    }

    function stop() {
        Jobs.cancel("perfmon-sys")
        Jobs.cancel("perfmon-gpu")
        procTimer.stop()
        firstRescan.stop()
        diskTimer.stop()
        prevCpu = null; prevNet = null; prevProc = null
        gpuValid = false
    }

    // one loop: sensors, /proc/stat, meminfo, net, cpu frequency, load; "E" ends a sample
    function startLoop() {
        const paths = sensors.map(s => s.path)
        Jobs.start("perfmon-sys", ["sh", "-c",
              'iv=$1; shift\n'
            + 'while :; do\n'
            + '  for f in "$@"; do printf "T %s %s\\n" "$f" "$(cat "$f" 2>/dev/null)"; done\n'
            + '  grep "^cpu" /proc/stat\n'
            + '  grep -E "^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):" /proc/meminfo\n'
            // physical traffic only: virtual interfaces would count it twice
            + '  sed "s/:/ /" /proc/net/dev | awk "NR>2 && \\$1 !~ /^(lo|docker|veth|br-|virbr|tailscale|wg|tun|vmnet|vboxnet)/ {rx+=\\$2; tx+=\\$10} END {print \\"NET\\", rx+0, tx+0}"\n'
            + '  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | awk "{s+=\\$1; n++} END {if (n) printf \\"FREQ %d\\\\n\\", s/n}"\n'
            + '  printf "LOAD %s\\n" "$(cut -d" " -f1-3 /proc/loadavg)"\n'
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
        if ((m = /^LOAD ([\d.]+) ([\d.]+) ([\d.]+)$/.exec(text))) { loadAvg = [Number(m[1]), Number(m[2]), Number(m[3])]; return }
        if (text === "E") { commit(cur); cur = {} }
    }

    function commit(c) {
        // sensors (millidegrees / rpm); a file that couldn't be read keeps its last value
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
            memFree = c.mem.MemFree ?? 0
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
        gpuValid = hasGpu && Date.now() - gpuTime < 3 * interval + 2000
        pushAll({ cpu: cpu, mem: mem, cpuTemp: cpuTemp, coolant: cooler?.coolant ?? -1, rx: prevNet ? netRx : -1, tx: prevNet ? netTx : -1,
                  gpu: gpuValid ? gpu.util : -1, gpuTemp: gpuValid ? gpu.temp : -1 })
    }

    function gpuLine(text) {
        const p = text.split(",").map(s => s.trim())
        if (p.length < 9) return
        const n = i => { const v = parseFloat(p[i]); return isNaN(v) ? -1 : v }
        gpu = { name: p[0], util: n(1), temp: n(2), memUsed: n(3), memTotal: n(4), power: n(5), powerLimit: n(6), clock: n(7), fan: n(8), memClock: n(9) }
        gpuTime = Date.now()
    }

    // ── processes ───────────────────────────────────────────────────────────
    // /proc/<pid>/stat of every process; CPU % = its ticks / all ticks since the
    // last scan (so 100 % = every core busy). One awk over all files, no per-
    // process programs. Fields after the ")" of the name: 4 ppid, 14+15 ticks,
    // 20 threads, 24 resident pages.
    property int pageSize: 4096
    property var prevProc: null             // { total, ticks: { pid: ticks } }
    property bool procBusy: false
    readonly property string procAwk: 'BEGIN { OFS = "\\t" } { s = $0; a = index(s, "("); m = match(s, /\\)[^)]*$/); '
        + 'split(substr(s, m + 2), f, " "); print substr(s, 1, a - 2), f[12] + f[13], f[22], f[2], f[18], substr(s, a + 1, m - a - 1) }'

    function scanProcs() {
        if (procBusy) return
        procBusy = true
        Jobs.run(["sh", "-c", 'head -n1 /proc/stat; awk "$1" /proc/[0-9]*/stat 2>/dev/null\n'
                 + 'if [ "$2" = 1 ]; then echo P; ps -eo pid=,user:32=,args= -ww | cut -c1-400; fi',
                  "sh", procAwk, procExtra ? "1" : "0"], (code, out) => {
            procBusy = false
            if (active) parseProcs(out)
        }, { LC_ALL: "C" })
    }

    function parseProcs(out) {
        const lines = out.split("\n")
        const total = (lines[0] ?? "").trim().split(/\s+/).slice(1).reduce((a, x) => a + Number(x), 0)
        const dt = prevProc ? total - prevProc.total : 0
        const ticks = {}, list = [], byPid = {}
        let threads = 0, i = 1
        for (; i < lines.length && lines[i] !== "P"; i++) {
            const p = lines[i].split("\t")
            if (p.length < 6) continue
            const pid = Number(p[0]), t = Number(p[1]), ppid = Number(p[3])
            ticks[pid] = t
            threads += Number(p[4]) || 0
            // a process started since the last scan: all its ticks are new
            const before = prevProc ? (prevProc.ticks[pid] ?? 0) : -1
            const e = { pid: pid, ppid: ppid, name: p.slice(5).join("\t"), threads: Number(p[4]) || 0,
                        cpu: before >= 0 && dt > 0 ? Math.max(0, 100 * (t - before) / dt) : -1,
                        mem: (Number(p[2]) || 0) * pageSize, kernel: pid === 2 || ppid === 2, user: "", cmd: "" }
            list.push(e)
            byPid[pid] = e
        }
        for (i++; i < lines.length; i++) {
            const m = /^\s*(\d+)\s+(\S+)\s*(.*)$/.exec(lines[i])
            const e = m ? byPid[Number(m[1])] : null
            if (e) { e.user = m[2]; e.cmd = m[3] }
        }
        if (total > 0) prevProc = { total: total, ticks: ticks }
        procs = list
        threadCount = threads
    }

    Timer {
        id: procTimer
        interval: root.procInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.scanProcs()
    }
    // the first scan only has totals: a second one soon after gives CPU %
    Timer { id: firstRescan; interval: 700; onTriggered: root.scanProcs() }

    // disks change slowly
    Timer {
        id: diskTimer
        interval: 10000
        repeat: true
        triggeredOnStart: true
        onTriggered: Jobs.run(["df", "-B1", "--output=source,fstype,target,used,size", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay"], (code, out) => {
            const seen = {}, d = []
            for (const l of out.split("\n").slice(1)) {
                const m = /^(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)$/.exec(l.trim())
                if (!m || seen[m[1]] || !m[1].startsWith("/dev/")) continue
                seen[m[1]] = true
                d.push({ device: m[1].replace("/dev/", ""), fs: m[2], mount: m[3], used: Number(m[4]), size: Number(m[5]) })
            }
            root.disks = d
        })
    }

    IpcHandler {
        target: "perfmon"
        function toggle(): void { Panels.toggle("perfmon") }
    }
}
