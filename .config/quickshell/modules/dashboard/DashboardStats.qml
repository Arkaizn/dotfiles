import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.services.lib
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io

ColumnLayout {
    id: root
    anchors.fill: parent
    anchors.margins: 10
    spacing: 8

    // set by the dashboard: true while it's open
    property bool active: false

    // ── Data ──────────────────────────────────────────────────────
    // SysStats (reads /proc and /sys) only while the dashboard is open; the
    // gauges take its numbers every 3 s, the slow facts (uptime, OS age,
    // disk) on open and once a minute
    onActiveChanged: active ? SysStats.acquire(3000) : SysStats.release(3000)
    Component.onDestruction: if (active) SysStats.release(3000)

    function sample() {
        cpuGauge.usage = Math.max(0, SysStats.cpu)
        cpuGauge.temp = Math.max(0, SysStats.cpuTemp)
        gpuGauge.usage = Math.max(0, SysStats.gpu)
        gpuGauge.temp = Math.max(0, SysStats.gpuTemp)
        if (SysStats.memTotal > 0) {
            ramGauge.usage = Math.floor(100 * SysStats.memUsed / SysStats.memTotal)
            ramGauge.detail = Format.freeH(SysStats.memUsed) + "/" + Format.freeH(SysStats.memTotal)
        }
        netGauge.rxKb = Math.floor(SysStats.rxRate / 1024)
        netGauge.txKb = Math.floor(SysStats.txRate / 1024)
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        blockLoading: true
        onLoaded: info.uptimeSecs = parseFloat(text()) || 0
    }
    Process {
        id: osAgeProc
        command: ["stat", "-c", "%W", "/"]
        stdout: SplitParser { onRead: data => { const b = parseInt(data); if (b > 0) info.osAge = Math.floor((Date.now() / 1000 - b) / 86400) + "d" } }
    }
    Process {
        id: diskProc
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: SplitParser { onRead: data => {
            const p = data.trim().split(/\s+/)
            if (isNaN(parseFloat(p[0]))) return // header line
            info.diskUsed = parseFloat(p[0])
            info.diskSize = parseFloat(p[1])
        }}
    }

    // on open: the last numbers at once, fresh ones as soon as SysStats has
    // read twice, then every 3 s
    Timer {
        interval: 3000; running: root.active; repeat: true; triggeredOnStart: true
        onTriggered: root.sample()
    }
    Timer { interval: 400; running: root.active; onTriggered: root.sample() }
    Timer {
        interval: 60000; running: root.active; repeat: true; triggeredOnStart: true
        onTriggered: {
            uptimeFile.reload()
            osAgeProc.running = true
            diskProc.running = true
        }
    }

    // ── Header ────────────────────────────────────────────────────

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: "SYSTEM"
        color: Colors.fade(0.35)
        font.pixelSize: 9
        font.letterSpacing: 3
        font.bold: true
    }

    // ── 2×2 gauge grid ────────────────────────────────────────────

    GridLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        columns: 2
        rowSpacing: 6
        columnSpacing: 6
        uniformCellWidths: true
        uniformCellHeights: true

        // CPU
        StatGauge {
            id: cpuGauge
            Layout.alignment: Qt.AlignHCenter
            label: "CPU"
            property int temp: 0
            property int usage: 0
            primaryValue: usage
            primaryMax: 100
            primaryColor: "#e05252"
            secondaryValue: temp
            secondaryMax: 100
            secondaryColor: "#f0a040"
            primaryLabel: usage + "%"
            secondaryLabel: temp + "°C"
        }

        // GPU
        StatGauge {
            id: gpuGauge
            Layout.alignment: Qt.AlignHCenter
            label: "GPU"
            property int temp: 0
            property int usage: 0
            primaryValue: usage
            primaryMax: 100
            primaryColor: "#52aaee"
            secondaryValue: temp
            secondaryMax: 100
            secondaryColor: "#a06ae0"
            primaryLabel: usage + "%"
            secondaryLabel: temp + "°C"
        }

        // RAM
        StatGauge {
            id: ramGauge
            Layout.alignment: Qt.AlignHCenter
            label: "RAM"
            property int usage: 0
            property string detail: ""
            primaryValue: usage
            primaryMax: 100
            primaryColor: "#52e0a0"
            secondaryValue: 0
            secondaryMax: 100
            secondaryColor: "transparent"
            primaryLabel: usage + "%"
            secondaryLabel: detail
            singleRing: true
        }

        // Network circle — left half = download, right half = upload
        Item {
            id: netGauge
            Layout.alignment: Qt.AlignHCenter
            width: 130; height: 130

            property int rxKb: 0
            property int txKb: 0
            // cap at 100 MB/s for arc fill
            property real rxPct: Math.min(rxKb / 102400.0, 1.0)
            property real txPct: Math.min(txKb / 102400.0, 1.0)

            property real animRx: 0
            Behavior on animRx { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onRxPctChanged: animRx = rxPct

            property real animTx: 0
            Behavior on animTx { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onTxPctChanged: animTx = txPct

            function fmt(kb) {
                if (kb >= 1024) return (kb / 1024).toFixed(1) + "\nMB/s"
                return kb + "\nKB/s"
            }

            // Ambient glow
            Rectangle {
                anchors.centerIn: parent
                width: 130; height: 130; radius: 65
                color: Qt.rgba(0.32, 0.87, 0.63, 0.05)
                // thin outline around the gauge circle
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder
            }

            // Download track (left half: 180°→360°, i.e. startAngle=180, sweep=180)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: Colors.fade(0.08); strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: 180; sweepAngle: 175 }
                }
            }
            // Upload track (right half: 0°→180°)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: Colors.fade(0.08); strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: 0; sweepAngle: 175 }
                }
            }

            // Download arc (left, green)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "#52e0a0"; strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 65; centerY: 65; radiusX: 50; radiusY: 50
                        startAngle: 180
                        sweepAngle: Math.max(0.01, 175 * netGauge.animRx)
                    }
                }
                layer.enabled: true
                layer.effect: Glow { radius: 6; samples: 13; color: "#52e0a0"; spread: 0.15; transparentBorder: true }
            }

            // Upload arc (right, red)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "#e05252"; strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 65; centerY: 65; radiusX: 50; radiusY: 50
                        startAngle: 0
                        sweepAngle: Math.max(0.01, 175 * netGauge.animTx)
                    }
                }
                layer.enabled: true
                layer.effect: Glow { radius: 6; samples: 13; color: "#e05252"; spread: 0.15; transparentBorder: true }
            }

            // Centre text
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    text: "NET"
                    color: Colors.fade(0.4)
                    font.pixelSize: 11; font.letterSpacing: 2; font.bold: true
                }
                Text {
                    text: "↓ " + (netGauge.rxKb >= 1024 ? (netGauge.rxKb/1024).toFixed(1)+"M" : netGauge.rxKb+"K")
                    color: "#52e0a0"
                    font.pixelSize: 12; font.bold: true
                }
                Text {
                    text: "↑ " + (netGauge.txKb >= 1024 ? (netGauge.txKb/1024).toFixed(1)+"M" : netGauge.txKb+"K")
                    color: "#e05252"
                    font.pixelSize: 12; font.bold: true
                }
            }
        }
    }

    // ── Info tiles: uptime + OS age, disk usage ───────────────────
    // Fills whatever height the gauges leave over.

    ColumnLayout {
        id: info
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: 2
        spacing: 6

        property real uptimeSecs: 0
        property string osAge: "—"
        property real diskUsed: 0
        property real diskSize: 0
        readonly property real diskPct: diskSize > 0 ? diskUsed / diskSize : 0

        // 3h 14m / 2d 5h / 42m
        function shortDuration(s) {
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
            if (d > 0) return d + "d " + h + "h"
            if (h > 0) return h + "h " + m + "m"
            return m + "m"
        }
        function bytes(b) {
            const t = 1024 ** 4, g = 1024 ** 3
            return b >= t ? (b / t).toFixed(1) + "T" : Math.round(b / g) + "G"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            InfoTile { icon: "󰔚"; label: "UPTIME"; value: info.uptimeSecs > 0 ? info.shortDuration(info.uptimeSecs) : "—" }
            InfoTile { icon: "󰣇"; label: "OS AGE"; value: info.osAge }
        }

        InfoTile {
            icon: "󰋊"
            label: "DISK  /"
            value: info.diskSize > 0
                ? info.bytes(info.diskUsed) + " / " + info.bytes(info.diskSize) + "   ·   " + Math.round(info.diskPct * 100) + "%"
                : "—"

            // usage bar — turns amber/red as the disk fills up
            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Colors.fade(0.08)

                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * info.diskPct
                    color: info.diskPct > 0.9 ? "#e05252" : info.diskPct > 0.75 ? "#e0a052" : "#52e0a0"
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    // ── StatGauge component ───────────────────────────────────────

    component StatGauge: Item {
        id: gauge

        property string label: "CPU"
        property int    primaryValue:   0
        property int    primaryMax:     100
        property color  primaryColor:   "#52aaee"
        property int    secondaryValue: 0
        property int    secondaryMax:   100
        property color  secondaryColor: "#f0a040"
        property string primaryLabel:   ""
        property string secondaryLabel: ""
        property bool   singleRing:     false

        // 2×2 grid in 300px (320 - 2×10 margin) with 6px gap → each cell ~147px
        // Keep gauge at 130 so glow has breathing room
        width: 130; height: 130

        property real animPrimary: 0
        Behavior on animPrimary { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        onPrimaryValueChanged: animPrimary = primaryValue

        property real animSecondary: 0
        Behavior on animSecondary { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        onSecondaryValueChanged: animSecondary = secondaryValue

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 130; height: 130; radius: 65
            color: Qt.rgba(gauge.primaryColor.r, gauge.primaryColor.g, gauge.primaryColor.b, 0.06)
            // thin outline around the gauge circle
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
        }

        // Shapes fill the Item exactly — center (65,65), outer r=50, inner r=36
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: Colors.fade(0.08); strokeWidth: 8
                fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: -225; sweepAngle: 270 }
            }
        }
        Shape {
            visible: !gauge.singleRing
            anchors.fill: parent
            ShapePath {
                strokeColor: Colors.fade(0.08); strokeWidth: 7
                fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 65; centerY: 65; radiusX: 36; radiusY: 36; startAngle: -225; sweepAngle: 270 }
            }
        }
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: gauge.primaryColor; strokeWidth: 8
                fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: -225
                    sweepAngle: Math.max(0.01, 270 * (gauge.animPrimary / Math.max(1, gauge.primaryMax)))
                }
            }
            layer.enabled: true
            layer.effect: Glow { radius: 6; samples: 13; color: gauge.primaryColor; spread: 0.15; transparentBorder: true }
        }
        Shape {
            visible: !gauge.singleRing
            anchors.fill: parent
            ShapePath {
                strokeColor: gauge.secondaryColor; strokeWidth: 7
                fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 65; centerY: 65; radiusX: 36; radiusY: 36; startAngle: -225
                    sweepAngle: Math.max(0.01, 270 * (gauge.animSecondary / Math.max(1, gauge.secondaryMax)))
                }
            }
            layer.enabled: true
            layer.effect: Glow { radius: 5; samples: 13; color: gauge.secondaryColor; spread: 0.15; transparentBorder: true }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: gauge.label
                color: Colors.fade(0.4)
                font.pixelSize: 11; font.letterSpacing: 2; font.bold: true
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: gauge.primaryLabel
                color: gauge.primaryColor
                font.pixelSize: gauge.singleRing ? 20 : 18
                font.bold: true
            }
            Text {
                visible: gauge.secondaryLabel !== ""
                Layout.alignment: Qt.AlignHCenter
                text: gauge.secondaryLabel
                color: gauge.singleRing ? Colors.fade(0.5) : gauge.secondaryColor
                font.pixelSize: gauge.singleRing ? 11 : 12
                font.bold: !gauge.singleRing
            }
        }
    }
}
