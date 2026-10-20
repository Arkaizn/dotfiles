import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services

// CPU / memory / CPU temperature / NVIDIA GPU, each with a bar or a history
// graph (SysStats, polled every 2 s while a widget shows), optional uptime.
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 10
    implicitWidth: 260

    property bool using: false
    function use(on) { if (on === using) return; using = on; on ? SysStats.acquire(2000) : SysStats.release(2000) }
    onActiveChanged: use(active)
    Component.onCompleted: use(active)
    Component.onDestruction: use(false)

    // 60 samples per row (2 minutes)
    property var hist: ({ cpu: [], mem: [], temp: [], gpu: [] })
    function push(k, v) {
        if (v < 0) return
        const h = Object.assign({}, hist)
        h[k] = hist[k].concat([v]).slice(-60)
        hist = h
    }
    Connections {
        target: SysStats
        function onCpuChanged() { root.push("cpu", SysStats.cpu) }
        function onMemChanged() { root.push("mem", SysStats.mem) }
        function onCpuTempChanged() { root.push("temp", SysStats.cpuTemp) }
        function onGpuChanged() { root.push("gpu", SysStats.gpu) }
    }

    readonly property var rows: [
        { key: "cpu", label: "CPU", icon: "󰍛", value: SysStats.cpu, text: SysStats.cpu + " %", max: 100 },
        { key: "mem", label: "Memory", icon: "󰘚", value: SysStats.mem,
          text: (SysStats.memUsed / 1048576).toFixed(1) + " / " + (SysStats.memTotal / 1048576).toFixed(0) + " GiB", max: 100 },
        { key: "temp", label: "CPU temp", icon: "󰔏", value: SysStats.cpuTemp, text: SysStats.cpuTemp + " °C", max: 100 },
        { key: "gpu", label: "GPU", icon: "󰢮", value: SysStats.gpu,
          text: SysStats.gpu + " %" + (SysStats.gpuTemp >= 0 ? "  " + SysStats.gpuTemp + " °C" : ""), max: 100 }
    ].filter(r => root.opts[r.key] !== false && r.value >= 0)

    Repeater {
        model: root.rows
        ColumnLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            readonly property color tint: modelData.key === "temp" && modelData.value >= 80 ? Colors.red : Colors.color6
            RowLayout {
                Layout.fillWidth: true
                Text { text: row.modelData.icon; color: row.tint; font.pixelSize: 14; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: row.modelData.label; color: Colors.fade(0.7); font.pixelSize: 12; font.family: Properties.fontFamily }
                Text { text: row.modelData.text; color: Colors.ink; font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
            }
            Spark {
                visible: root.opts.graph !== false
                Layout.fillWidth: true
                values: root.hist[row.modelData.key]
                max: row.modelData.max
                color: row.tint
            }
            Rectangle {
                visible: root.opts.graph === false
                Layout.fillWidth: true
                implicitHeight: 4; radius: 2
                color: Colors.fade(0.12)
                Rectangle {
                    width: parent.width * Math.min(1, row.modelData.value / row.modelData.max)
                    height: parent.height; radius: 2
                    color: row.tint
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }
        }
    }

    // uptime (every minute while shown)
    property string uptime: ""
    FileView {
        id: up
        path: "/proc/uptime"
        blockLoading: true
        onLoaded: {
            const s = Math.floor(parseFloat(text()))
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
            root.uptime = (d > 0 ? d + " d " : "") + h + " h " + m + " min"
        }
    }
    Timer { running: root.active && root.opts.uptime === true; interval: 60000; repeat: true; triggeredOnStart: true; onTriggered: up.reload() }
    Text {
        visible: root.opts.uptime === true
        text: "󰔛  up " + root.uptime
        color: Colors.fade(0.6)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
}
