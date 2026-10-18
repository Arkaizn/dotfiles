import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Performance monitor (CAM-style): gauges for CPU / GPU / memory / liquid
// cooler, load and temperature history, and details. Data: services/PerfMon.qml,
// which only runs while this window is open.
//   qs ipc call perfmon toggle
Scope {
    id: root
    property bool open: false
    Connections { target: PerfMon; function onToggleRequested() { root.open = !root.open } }
    onOpenChanged: PerfMon.active = open

    readonly property color cpuColor: Colors.color6
    readonly property color gpuColor: Colors.green
    readonly property color memColor: Colors.blue
    readonly property color liquidColor: Colors.teal

    function gb(kib) { return (kib / 1048576).toFixed(1) }

    LazyLoader {
        active: root.open
        FloatingWindow {
            title: "Performance"
            visible: true
            implicitWidth: 1120
            implicitHeight: 780
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.96)
            onClosed: root.open = false

            Flickable {
                anchors.fill: parent
                contentHeight: page.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: page
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Performance"; color: Colors.ink; font.pixelSize: 22; font.bold: true; font.family: Properties.fontFamily }
                        Item { Layout.fillWidth: true }
                        Text { text: "every " + (PerfMon.interval / 1000) + " s  ·  only while this window is open"; color: Colors.fade(0.4); font.pixelSize: 11; font.family: Properties.fontFamily }
                    }

                    // ── gauges ──────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            title: "CPU"; icon: ""; note: PerfMon.cpuFreq > 0 ? (PerfMon.cpuFreq / 1000).toFixed(2) + " GHz" : ""
                            Gauge { Layout.alignment: Qt.AlignHCenter; value: PerfMon.cpu; sub: PerfMon.cpuTemp > 0 ? Math.round(PerfMon.cpuTemp) + " °C" : "" }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            visible: PerfMon.hasGpu
                            title: "GPU"; icon: "󰢮"; note: PerfMon.gpu.clock > 0 ? PerfMon.gpu.clock + " MHz" : ""
                            Gauge { Layout.alignment: Qt.AlignHCenter; value: PerfMon.gpu.util ?? -1; sub: (PerfMon.gpu.temp ?? -1) > 0 ? PerfMon.gpu.temp + " °C" : "" }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            title: "Memory"; icon: ""; note: PerfMon.memTotal > 0 ? root.gb(PerfMon.memTotal) + " GB" : ""
                            Gauge { Layout.alignment: Qt.AlignHCenter; value: PerfMon.mem; warn: 80; crit: 92; sub: root.gb(PerfMon.memUsed) + " GB used" }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            visible: PerfMon.cooler !== null
                            title: "Liquid"; icon: "󰖌"; note: (PerfMon.cooler?.pump ?? -1) > 0 ? "pump " + PerfMon.cooler.pump + " rpm" : ""
                            Gauge {
                                Layout.alignment: Qt.AlignHCenter
                                value: PerfMon.cooler?.coolant ?? -1
                                min: 20; max: 60; warn: 45; crit: 52
                                text: value < 0 ? "–" : value.toFixed(1) + "°"
                                sub: (PerfMon.cooler?.fan ?? -1) > 0 ? "fan " + PerfMon.cooler.fan + " rpm" : "coolant"
                            }
                        }
                    }

                    // ── history ─────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            title: "Load"
                            note: "<font color='" + root.cpuColor + "'>CPU</font>  <font color='" + root.gpuColor + "'>GPU</font>  <font color='" + root.memColor + "'>RAM</font>"
                            Chart {
                                Layout.fillWidth: true; implicitHeight: 150
                                length: PerfMon.historyLength; unit: "%"
                                series: [{ values: PerfMon.hist.cpu, color: root.cpuColor, fill: true },
                                         { values: PerfMon.hist.gpu, color: root.gpuColor },
                                         { values: PerfMon.hist.mem, color: root.memColor }]
                            }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            title: "Temperatures"
                            note: "<font color='" + root.cpuColor + "'>CPU</font>  <font color='" + root.gpuColor + "'>GPU</font>" + (PerfMon.cooler ? "  <font color='" + root.liquidColor + "'>liquid</font>" : "")
                            Chart {
                                Layout.fillWidth: true; implicitHeight: 150
                                length: PerfMon.historyLength; min: 20; max: 100; unit: "°"
                                series: [{ values: PerfMon.hist.cpuTemp, color: root.cpuColor, fill: true },
                                         { values: PerfMon.hist.gpuTemp, color: root.gpuColor },
                                         { values: PerfMon.hist.coolant, color: root.liquidColor }]
                            }
                        }
                    }

                    // ── details ─────────────────────────────────────────────
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 14
                        rowSpacing: 14

                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: PerfMon.gpu.name ?? "GPU"; icon: "󰢮"
                            visible: PerfMon.hasGpu
                            InfoRow { label: "Video memory"; value: (PerfMon.gpu.memUsed / 1024).toFixed(1) + " / " + (PerfMon.gpu.memTotal / 1024).toFixed(1) + " GB"; bar: PerfMon.gpu.memTotal > 0 ? PerfMon.gpu.memUsed / PerfMon.gpu.memTotal : -1; barColor: root.gpuColor }
                            InfoRow { label: "Power"; value: Math.round(PerfMon.gpu.power ?? 0) + " / " + Math.round(PerfMon.gpu.powerLimit ?? 0) + " W"; bar: PerfMon.gpu.powerLimit > 0 ? PerfMon.gpu.power / PerfMon.gpu.powerLimit : -1; barColor: root.gpuColor }
                            InfoRow { label: "Core clock"; value: (PerfMon.gpu.clock ?? 0) + " MHz" }
                            InfoRow { label: "Fan"; value: (PerfMon.gpu.fan ?? 0) <= 0 ? "stopped (0 rpm mode)" : PerfMon.gpu.fan + " %" }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: "CPU cores"; icon: ""; note: PerfMon.cores.length + " threads"
                            Grid {
                                Layout.fillWidth: true
                                columns: 8
                                spacing: 4
                                // count models: the delegates stay, only their values change each second
                                // (a new array as model would rebuild every delegate every tick)
                                Repeater {
                                    model: PerfMon.cores.length
                                    Rectangle {
                                        required property int index
                                        readonly property real modelData: PerfMon.cores[index] ?? 0
                                        width: 30; height: 46; radius: 5
                                        color: Colors.fade(0.06)
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: parent.height * Math.min(1, modelData / 100)
                                            radius: 5
                                            color: modelData > 90 ? Colors.red : modelData > 75 ? Colors.yellow : root.cpuColor
                                        }
                                    }
                                }
                            }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: "Network"; icon: "󰛳"
                            InfoRow { label: "󰇚 down"; value: PerfMon.bytes(PerfMon.netRx) + "/s" }
                            InfoRow { label: "󰕒 up"; value: PerfMon.bytes(PerfMon.netTx) + "/s" }
                            Chart {
                                Layout.fillWidth: true; implicitHeight: 60
                                length: PerfMon.historyLength; max: -1
                                series: [{ values: PerfMon.hist.rx, color: root.memColor, fill: true }, { values: PerfMon.hist.tx, color: root.gpuColor }]
                            }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: "Disks"; icon: "󰋊"
                            Repeater {
                                model: PerfMon.disks.length
                                InfoRow {
                                    required property int index
                                    readonly property var modelData: PerfMon.disks[index] ?? ({ mount: "", used: 0, size: 0 })
                                    label: modelData.mount
                                    value: PerfMon.bytes(modelData.used) + " / " + PerfMon.bytes(modelData.size)
                                    bar: modelData.size > 0 ? modelData.used / modelData.size : -1
                                }
                            }
                            InfoRow { visible: PerfMon.swapTotal > 0; label: "Swap"; value: root.gb(PerfMon.swapUsed) + " / " + root.gb(PerfMon.swapTotal) + " GB"; bar: PerfMon.swapTotal > 0 ? PerfMon.swapUsed / PerfMon.swapTotal : -1 }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: "Sensors"; icon: "󰔏"
                            Repeater {
                                model: PerfMon.shownSensors.length
                                InfoRow {
                                    required property int index
                                    readonly property var modelData: PerfMon.shownSensors[index] ?? ({ chip: "", label: "", kind: "temp", value: 0 })
                                    label: modelData.chip + " · " + modelData.label
                                    value: modelData.kind === "temp" ? modelData.value.toFixed(1) + " °C" : modelData.value + " rpm"
                                }
                            }
                        }
                        PerfCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                            title: "Top processes"; icon: "󰍛"; note: "CPU · RAM"
                            Repeater {
                                model: PerfMon.procs.length
                                InfoRow {
                                    required property int index
                                    readonly property var modelData: PerfMon.procs[index] ?? ({ name: "", cpu: 0, mem: 0 })
                                    label: modelData.name
                                    value: modelData.cpu.toFixed(1) + "%  ·  " + modelData.mem.toFixed(1) + "%"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
