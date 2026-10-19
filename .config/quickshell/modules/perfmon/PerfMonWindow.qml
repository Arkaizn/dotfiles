import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Performance monitor (inspired by NZXT CAM): an overview of gauges, load /
// temperature history, CPU / GPU / memory details, a process table, network
// and every sensor. Solid background (no blur), in the settings app's style.
// Data: services/PerfMon.qml, which only runs while this window is open.
//   qs ipc call perfmon toggle
Scope {
    id: root
    property bool open: false
    Connections { target: PerfMon; function onToggleRequested() { root.open = !root.open } }
    onOpenChanged: PerfMon.active = open

    // one color per component, the same everywhere (gauges, charts, bars)
    readonly property color cpuColor: Colors.color6
    readonly property color gpuColor: Colors.blue
    readonly property color memColor: Colors.green
    readonly property color liquidColor: Colors.teal
    readonly property color rxColor: Colors.teal
    readonly property color txColor: Colors.orange

    // chart range (kept in Settings.perfmon.chartRange)
    readonly property var ranges: ({ "1 min": 60, "5 min": 300, "15 min": 900 })
    readonly property string rangeName: ranges[Settings.perfmon.chartRange] ? Settings.perfmon.chartRange : "1 min"
    readonly property int span: Math.round(ranges[rangeName] * 1000 / PerfMon.interval)

    function gib(kib) { return (kib / 1048576).toFixed(1) }
    function temp(v) { return v > 0 ? v.toFixed(1) + " °C" : "–" }
    function ghz(mhz) { return mhz > 0 ? (mhz / 1000).toFixed(2) + " GHz" : "–" }

    // sensors grouped by chip, with readable names
    function chipName(chip) {
        if (/^k10temp|^coretemp|^zenpower/.test(chip)) return "CPU"
        if (/^kraken|^nzxt/i.test(chip)) return "Liquid cooler"
        if (/^nvme/.test(chip)) return "NVMe drive"
        if (/^spd5118|^jc42/.test(chip)) return "Memory module"
        if (/^asusec|^nct|^it87|^asus_wmi/.test(chip)) return "Motherboard"
        if (/^amdgpu|^nouveau/.test(chip)) return "GPU"
        if (/^mt79|^iwlwifi|^ath/.test(chip)) return "Wi-Fi"
        if (/^acpitz/.test(chip)) return "ACPI"
        return chip
    }
    readonly property var sensorGroups: {
        const groups = [], byHwmon = {}
        for (const s of PerfMon.shownSensors) {
            let g = byHwmon[s.hwmon]
            if (!g) { g = byHwmon[s.hwmon] = { name: chipName(s.chip), chip: s.chip, items: [] }; groups.push(g) }
            g.items.push(s)
        }
        // the same kind twice (two drives, two DIMMs): number them
        const count = {}
        for (const g of groups) count[g.name] = (count[g.name] ?? 0) + 1
        const seen = {}
        for (const g of groups) if (count[g.name] > 1) { seen[g.name] = (seen[g.name] ?? 0) + 1; g.name += " " + seen[g.name] }
        return groups
    }

    LazyLoader {
        active: root.open
        FloatingWindow {
            id: win
            title: "Performance"
            visible: true
            implicitWidth: 1280
            implicitHeight: 900
            minimumSize: Qt.size(820, 560)
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 1)
            onClosed: root.open = false

            readonly property bool wide: width >= 1140
            readonly property real pageWidth: width - 40

            Shortcut { sequences: [StandardKey.Find, "/"]; onActivated: procs.focusSearch() }

            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: page.implicitHeight + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                SmoothWheel { flick: flick; step: 100 }

                ColumnLayout {
                    id: page
                    x: 20; y: 16
                    width: win.pageWidth
                    spacing: 12

                    // ── title ───────────────────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        DragHandler { target: null; onActiveChanged: if (active) page.Window.window.startSystemMove() }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 10
                            Text { text: "󰓅"; color: Colors.color6; font.pixelSize: 22; font.family: Properties.fontFamily }
                            ColumnLayout {
                                spacing: 0
                                Text { text: "Performance"; color: Colors.ink; font.pixelSize: 18; font.bold: true; font.family: Properties.fontFamily }
                                Text {
                                    text: [PerfMon.cpuName, PerfMon.hasGpu ? PerfMon.gpu.name ?? "" : "",
                                           PerfMon.memTotal > 0 ? Math.round(PerfMon.memTotal / 1048576) + " GiB RAM" : ""].filter(x => x).join("  ·  ")
                                    color: Colors.fade(0.45)
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "History"; color: Colors.fade(0.45); font.pixelSize: 11; font.family: Properties.fontFamily }
                            ChoiceControl {
                                options: Object.keys(root.ranges)
                                value: root.rangeName
                                onEdited: v => v === "1 min" ? Settings.reset("perfmon", "chartRange") : Settings.set("perfmon", "chartRange", v)
                            }
                        }
                    }

                    // ── overview ────────────────────────────────────────────
                    PerfCard {
                        Layout.fillWidth: true
                        padding: 16
                        title: "Overview"
                        icon: "󰄪"
                        note: "updates every " + (PerfMon.interval / 1000) + " s while this window is open"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            OverviewGauge {
                                label: "CPU"; accent: root.cpuColor
                                value: PerfMon.cpu
                                sub: PerfMon.cpuTemp > 0 ? Math.round(PerfMon.cpuTemp) + " °C" : ""
                                caption: root.ghz(PerfMon.cpuFreq)
                            }
                            OverviewGauge {
                                visible: PerfMon.hasGpu
                                label: "GPU"; accent: root.gpuColor
                                value: PerfMon.gpuValid ? PerfMon.gpu.util : -1
                                sub: PerfMon.gpuValid && PerfMon.gpu.temp > 0 ? PerfMon.gpu.temp + " °C" : ""
                                caption: PerfMon.gpuValid ? (PerfMon.gpu.clock > 0 ? PerfMon.gpu.clock + " MHz" : "") + (PerfMon.gpu.power >= 0 ? "  ·  " + Math.round(PerfMon.gpu.power) + " W" : "") : "no data"
                            }
                            OverviewGauge {
                                label: "Memory"; accent: root.memColor
                                value: PerfMon.mem; warn: 80; crit: 92
                                sub: PerfMon.memTotal > 0 ? root.gib(PerfMon.memUsed) + " GiB" : ""
                                caption: PerfMon.memTotal > 0 ? "of " + root.gib(PerfMon.memTotal) + " GiB" : ""
                            }
                            OverviewGauge {
                                visible: PerfMon.cooler !== null
                                label: "Liquid"; accent: root.liquidColor
                                value: PerfMon.cooler?.coolant ?? -1
                                min: 20; max: 60; warn: 45; crit: 52
                                text: value < 0 ? "–" : value.toFixed(1)
                                unit: value < 0 ? "" : "°C"
                                sub: "coolant"
                                caption: (PerfMon.cooler?.pump ?? -1) > 0 ? "pump " + PerfMon.cooler.pump + " rpm" : ""
                            }
                            // fans: rpm has no fixed maximum, so a list instead of gauges
                            Rectangle {
                                visible: fanList.count > 0 || gpuFan.visible
                                Layout.fillHeight: true
                                implicitWidth: 1
                                color: Properties.cardBorder
                            }
                            ColumnLayout {
                                visible: fanList.count > 0 || gpuFan.visible
                                Layout.preferredWidth: 250
                                Layout.leftMargin: 8
                                Layout.rightMargin: 4
                                Layout.alignment: Qt.AlignTop
                                spacing: 6
                                CapsLabel { text: "FANS"; dot: Colors.fade(0.5) }
                                Repeater {
                                    id: fanList
                                    model: PerfMon.fans.length
                                    FanRow {
                                        required property int index
                                        readonly property var s: PerfMon.fans[index] ?? ({ chip: "", label: "", value: 0 })
                                        name: (/^kraken|^nzxt/i.test(s.chip) ? "Kraken " : "") + s.label.replace(/ speed$/i, "")
                                        value: s.value > 0 ? s.value + " rpm" : "stopped"
                                    }
                                }
                                FanRow {
                                    id: gpuFan
                                    visible: PerfMon.gpuValid && PerfMon.gpu.fan >= 0
                                    name: "GPU"
                                    value: PerfMon.gpu.fan > 0 ? PerfMon.gpu.fan + " %" : "0 rpm mode"
                                }
                            }
                        }
                    }

                    // ── history ─────────────────────────────────────────────
                    GridLayout {
                        Layout.fillWidth: true
                        columns: win.wide ? 2 : 1
                        columnSpacing: 12
                        rowSpacing: 12
                        uniformCellWidths: true
                        ChartCard {
                            span: root.span
                            title: "Load"; icon: "󰄪"
                            chart.format: v => Math.round(v) + "%"
                            seriesList: [{ label: "CPU", values: PerfMon.hist.cpu, color: root.cpuColor, fill: true },
                                         { label: "GPU", values: PerfMon.hist.gpu, color: root.gpuColor, show: PerfMon.hasGpu },
                                         { label: "RAM", values: PerfMon.hist.mem, color: root.memColor }]
                        }
                        ChartCard {
                            span: root.span
                            title: "Temperatures"; icon: "󰔏"
                            chart.autoRange: true
                            chart.min: 0; chart.max: 100; chart.step: 10
                            chart.format: v => Math.round(v) + "°"
                            seriesList: [{ label: "CPU", values: PerfMon.hist.cpuTemp, color: root.cpuColor, fill: true },
                                         { label: "GPU", values: PerfMon.hist.gpuTemp, color: root.gpuColor, show: PerfMon.hasGpu },
                                         { label: "Liquid", values: PerfMon.hist.coolant, color: root.liquidColor, show: PerfMon.cooler !== null }]
                        }
                    }

                    // ── details ─────────────────────────────────────────────
                    GridLayout {
                        Layout.fillWidth: true
                        columns: win.wide ? 3 : 2
                        columnSpacing: 12
                        rowSpacing: 12
                        uniformCellWidths: true

                        // CPU
                        PerfCard {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            title: "CPU"; icon: Icons.get("cpuUsage"); iconColor: root.cpuColor
                            note: PerfMon.cpuName
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Stat { label: "LOAD"; value: PerfMon.cpu < 0 ? "–" : PerfMon.cpu + "%" }
                                Stat { label: "CLOCK"; value: root.ghz(PerfMon.cpuFreq) }
                                Stat { label: "TEMP"; value: root.temp(PerfMon.cpuTemp) }
                            }
                            CapsLabel { text: PerfMon.cores.length + " THREADS"; Layout.topMargin: 2 }
                            // per-thread load; count model, so the bars stay and only their heights change
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 52
                                Row {
                                    id: coreRow
                                    anchors.fill: parent
                                    spacing: 3
                                    readonly property real barW: PerfMon.cores.length > 0 ? (width - spacing * (PerfMon.cores.length - 1)) / PerfMon.cores.length : 0
                                    Repeater {
                                        model: PerfMon.cores.length
                                        Rectangle {
                                            required property int index
                                            readonly property real v: PerfMon.cores[index] ?? 0
                                            width: coreRow.barW; height: coreRow.height; radius: 3
                                            color: Colors.fade(0.06)
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                height: Math.max(2, parent.height * Math.min(1, v / 100))
                                                radius: 3
                                                color: v > 90 ? Colors.red : v > 75 ? Colors.yellow : root.cpuColor
                                                opacity: 0.35 + 0.65 * Math.min(1, v / 50)
                                            }
                                            HoverHandler { id: coreHover }
                                            ToolTip.visible: coreHover.hovered
                                            ToolTip.text: "Thread " + index + ": " + v + "%"
                                        }
                                    }
                                }
                            }
                            InfoRow { label: "Load  1 · 5 · 15 min"; value: PerfMon.loadAvg.length ? PerfMon.loadAvg.map(x => x.toFixed(2)).join("  ·  ") : "–" }
                            InfoRow { label: "Processes"; value: PerfMon.procs.length > 0 ? String(PerfMon.procs.length) : "–"; detail: PerfMon.threadCount > 0 ? PerfMon.threadCount + " threads" : "" }
                        }

                        // GPU
                        PerfCard {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: PerfMon.hasGpu
                            title: "GPU"; icon: Icons.get("gpu"); iconColor: root.gpuColor
                            note: PerfMon.gpu.name ?? ""
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Stat { label: "CLOCK"; value: PerfMon.gpuValid && PerfMon.gpu.clock >= 0 ? PerfMon.gpu.clock + " MHz" : "–" }
                                Stat { label: "TEMP"; value: PerfMon.gpuValid ? root.temp(PerfMon.gpu.temp) : "–" }
                                Stat { label: "FAN"; value: !PerfMon.gpuValid || PerfMon.gpu.fan < 0 ? "–" : PerfMon.gpu.fan === 0 ? "0 rpm mode" : PerfMon.gpu.fan + " %" }
                            }
                            InfoRow {
                                label: "Utilization"
                                value: PerfMon.gpuValid && PerfMon.gpu.util >= 0 ? PerfMon.gpu.util + "%" : "–"
                                bar: PerfMon.gpuValid ? PerfMon.gpu.util / 100 : -1; barColor: root.gpuColor
                            }
                            InfoRow {
                                label: "Video memory"
                                value: PerfMon.gpuValid && PerfMon.gpu.memTotal > 0 ? (PerfMon.gpu.memUsed / 1024).toFixed(1) + " / " + (PerfMon.gpu.memTotal / 1024).toFixed(1) + " GiB" : "–"
                                bar: PerfMon.gpuValid && PerfMon.gpu.memTotal > 0 ? PerfMon.gpu.memUsed / PerfMon.gpu.memTotal : -1; barColor: root.gpuColor
                            }
                            InfoRow {
                                label: "Power"
                                value: PerfMon.gpuValid && PerfMon.gpu.power >= 0 ? Math.round(PerfMon.gpu.power) + (PerfMon.gpu.powerLimit > 0 ? " / " + Math.round(PerfMon.gpu.powerLimit) : "") + " W" : "–"
                                bar: PerfMon.gpuValid && PerfMon.gpu.powerLimit > 0 ? PerfMon.gpu.power / PerfMon.gpu.powerLimit : -1; barColor: root.gpuColor
                            }
                            InfoRow { visible: PerfMon.gpuValid && PerfMon.gpu.memClock > 0; label: "Memory clock"; value: PerfMon.gpu.memClock + " MHz" }
                            Text {
                                visible: !PerfMon.gpuValid
                                text: "Waiting for nvidia-smi…"
                                color: Colors.fade(0.4)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                        }

                        // memory & storage
                        PerfCard {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.columnSpan: win.wide || !PerfMon.hasGpu ? 1 : 2
                            title: "Memory & storage"; icon: Icons.get("memory"); iconColor: root.memColor
                            // used | cache the kernel can give back | free
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: PerfMon.memTotal > 0 ? root.gib(PerfMon.memUsed) + " GiB" : "–"; color: Colors.ink; font.pixelSize: 16; font.bold: true; font.family: Properties.fontFamily }
                                Text { Layout.fillWidth: true; text: PerfMon.memTotal > 0 ? "used of " + root.gib(PerfMon.memTotal) + " GiB" : ""; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
                                Text { text: PerfMon.mem >= 0 ? Math.round(PerfMon.mem) + "%" : ""; color: Colors.fade(0.7); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
                            }
                            Rectangle {
                                id: memBar
                                Layout.fillWidth: true
                                implicitHeight: 8
                                radius: 4
                                color: Colors.fade(0.07)
                                readonly property real t: Math.max(1, PerfMon.memTotal)
                                readonly property real cache: Math.max(0, PerfMon.memTotal - PerfMon.memUsed - PerfMon.memFree)
                                Rectangle { x: 0; width: memBar.width * PerfMon.memUsed / memBar.t; height: parent.height; radius: 4
                                            color: PerfMon.mem > 92 ? Colors.red : PerfMon.mem > 80 ? Colors.yellow : root.memColor }
                                Rectangle { x: memBar.width * PerfMon.memUsed / memBar.t; width: memBar.width * memBar.cache / memBar.t; height: parent.height; radius: 4
                                            color: Qt.rgba(root.memColor.r, root.memColor.g, root.memColor.b, 0.3) }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Legend { color: root.memColor; text: "Used " + root.gib(PerfMon.memUsed) + " GiB" }
                                Legend { color: Qt.rgba(root.memColor.r, root.memColor.g, root.memColor.b, 0.35); text: "Cache " + root.gib(Math.max(0, PerfMon.memTotal - PerfMon.memUsed - PerfMon.memFree)) + " GiB" }
                                Legend { color: Colors.fade(0.15); text: "Free " + root.gib(PerfMon.memFree) + " GiB" }
                                Item { Layout.fillWidth: true }
                            }
                            InfoRow {
                                visible: PerfMon.swapTotal > 0
                                label: "Swap"
                                value: root.gib(PerfMon.swapUsed) + " / " + root.gib(PerfMon.swapTotal) + " GiB"
                                bar: PerfMon.swapTotal > 0 ? PerfMon.swapUsed / PerfMon.swapTotal : -1; barColor: root.memColor
                            }
                            CapsLabel { text: "STORAGE"; Layout.topMargin: 4 }
                            Repeater {
                                model: PerfMon.disks.length
                                ColumnLayout {
                                    id: disk
                                    required property int index
                                    readonly property var d: PerfMon.disks[index] ?? ({ device: "", fs: "", mount: "", used: 0, size: 0 })
                                    readonly property real frac: d.size > 0 ? d.used / d.size : 0
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: "󰋊"; color: Colors.fade(0.5); font.pixelSize: 13; font.family: Properties.fontFamily }
                                        Text { text: disk.d.mount; color: Colors.ink; font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideMiddle; Layout.maximumWidth: 140 }
                                        Text { Layout.fillWidth: true; text: disk.d.device + " · " + disk.d.fs; color: Colors.fade(0.4); font.pixelSize: 11; font.family: Properties.fontFamily; elide: Text.ElideRight }
                                        Text { text: PerfMon.ibytes(disk.d.used) + " / " + PerfMon.ibytes(disk.d.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                                        Text { Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight; text: Math.round(disk.frac * 100) + "%"; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 5
                                        radius: 2.5
                                        color: Colors.fade(0.07)
                                        Rectangle { width: parent.width * disk.frac; height: parent.height; radius: 2.5
                                                    color: disk.frac > 0.9 ? Colors.red : disk.frac > 0.8 ? Colors.yellow : Colors.fade(0.45) }
                                    }
                                }
                            }
                            Text {
                                visible: PerfMon.disks.length === 0
                                text: "Reading disks…"
                                color: Colors.fade(0.4)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                        }
                    }

                    // ── processes, network, sensors ─────────────────────────
                    GridLayout {
                        Layout.fillWidth: true
                        columns: win.wide ? 2 : 1
                        columnSpacing: 12
                        rowSpacing: 12

                        ProcessTable {
                            id: procs
                            Layout.fillWidth: true
                            Layout.preferredWidth: 2
                            Layout.preferredHeight: 560
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.maximumWidth: win.wide ? 440 : 100000
                            Layout.preferredHeight: win.wide ? 560 : -1
                            Layout.fillHeight: true
                            spacing: 12

                            PerfCard {
                                Layout.fillWidth: true
                                title: "Network"; icon: "󰌗"; iconColor: root.rxColor
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Stat { label: "󰇚 DOWN"; labelColor: root.rxColor; value: PerfMon.ibytes(PerfMon.netRx) + "/s" }
                                    Stat { label: "󰕒 UP"; labelColor: root.txColor; value: PerfMon.ibytes(PerfMon.netTx) + "/s" }
                                }
                                Chart {
                                    Layout.fillWidth: true
                                    implicitHeight: 110
                                    span: root.span
                                    interval: PerfMon.interval
                                    autoRange: true; zeroBased: true; binary: true
                                    min: 0; max: 1024
                                    gutter: 62
                                    gridLines: 2
                                    format: v => PerfMon.ibytes(v) + "/s"
                                    series: [{ label: "Down", values: PerfMon.hist.rx, color: root.rxColor, fill: true },
                                             { label: "Up", values: PerfMon.hist.tx, color: root.txColor }]
                                }
                            }

                            PerfCard {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredHeight: win.wide ? -1 : 360
                                title: "Sensors"; icon: "󰔏"
                                note: PerfMon.shownSensors.length + " readings"
                                ListView {
                                    id: sensorList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 120
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    spacing: 10
                                    // count model: the groups only change when sensors come or go
                                    model: root.sensorGroups.length
                                    ScrollBar.vertical: ScrollBar { policy: sensorList.contentHeight > sensorList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                                    delegate: ColumnLayout {
                                        id: group
                                        required property int index
                                        readonly property var g: root.sensorGroups[index] ?? ({ name: "", chip: "", items: [] })
                                        width: ListView.view.width - 8
                                        spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            CapsLabel { text: group.g.name.toUpperCase() }
                                            Text { Layout.fillWidth: true; text: group.g.chip; color: Colors.fade(0.28); font.pixelSize: 10; font.family: Properties.fontFamily; elide: Text.ElideRight }
                                        }
                                        Repeater {
                                            model: group.g.items.length
                                            RowLayout {
                                                required property int index
                                                readonly property var s: group.g.items[index] ?? ({ label: "", kind: "temp", value: 0 })
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Text { text: parent.s.kind === "fan" ? "󰈐" : "󰔏"; color: Colors.fade(0.35); font.pixelSize: 12; font.family: Properties.fontFamily }
                                                Text { Layout.fillWidth: true; text: parent.s.label; color: Colors.fade(0.7); font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideRight }
                                                Text {
                                                    text: parent.s.kind === "temp" ? parent.s.value.toFixed(1) + " °C" : parent.s.value + " rpm"
                                                    color: parent.s.kind === "temp" && parent.s.value >= 85 ? Colors.red : parent.s.kind === "temp" && parent.s.value >= 70 ? Colors.yellow : Colors.ink
                                                    font.pixelSize: 12
                                                    font.family: Properties.fontFamily
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: sensorList.count === 0
                                        text: PerfMon.sensors.length === 0 ? "No hwmon sensors found" : "Reading sensors…"
                                        color: Colors.fade(0.4)
                                        font.pixelSize: 12
                                        font.family: Properties.fontFamily
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
