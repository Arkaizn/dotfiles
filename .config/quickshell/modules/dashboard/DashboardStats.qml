import QtQuick
import Quickshell
import qs.components
import qs.services
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

    // ── Data sources ──────────────────────────────────────────────

    Process {
        id: cpuTempProc
        command: ["bash", "-lc",
            "sensors 2>/dev/null | awk '/Tctl:/{gsub(/[^0-9.]/,\" \",$2); printf \"%d\", $2; exit}'"]
        running: true
        stdout: SplitParser { onRead: data => { var v = parseInt(data); if (v > 0) cpuGauge.temp = v } }
    }
    Process {
        id: cpuUsageProc
        command: ["bash", "-lc",
            "top -bn1 | grep -E '^(%Cpu|Cpu)' | awk '{for(i=1;i<=NF;i++) if($i~/id/) {idle=$(i-1); gsub(/,/,\".\",idle); printf \"%d\", 100-idle; exit}}'"]
        running: true
        stdout: SplitParser { onRead: data => cpuGauge.usage = parseInt(data) || 0 }
    }
    Process {
        id: gpuTempProc
        command: ["bash", "-lc",
            "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1"]
        running: true
        stdout: SplitParser { onRead: data => gpuGauge.temp = parseInt(data) || 0 }
    }
    Process {
        id: gpuUsageProc
        command: ["bash", "-lc",
            "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1"]
        running: true
        stdout: SplitParser { onRead: data => gpuGauge.usage = parseInt(data) || 0 }
    }
    Process {
        id: ramUsageProc
        command: ["bash", "-lc",
            "free | awk '/Mem:/ {printf \"%d\", int($3/$2*100)}'"]
        running: true
        stdout: SplitParser { onRead: data => ramGauge.usage = parseInt(data) || 0 }
    }
    Process {
        id: ramDetailProc
        command: ["bash", "-lc",
            "free -h | awk '/Mem:/ {print $3 \"/\" $2}'"]
        running: true
        stdout: SplitParser { onRead: data => ramGauge.detail = data.trim() }
    }
    Process {
        id: netProc
        command: ["bash", "-lc",
            "awk 'NR>2{rx+=$2;tx+=$10}END{print rx,tx}' /proc/net/dev>/tmp/qs_n0; sleep 1; awk 'NR>2{rx+=$2;tx+=$10}END{print rx,tx}' /proc/net/dev>/tmp/qs_n1; paste /tmp/qs_n0 /tmp/qs_n1|awk '{d=$3-$1;u=$4-$2;if(d<0)d=0;if(u<0)u=0;printf \"%d %d\",d/1024,u/1024}'"]
        running: true
        stdout: SplitParser { onRead: data => {
            var parts = data.trim().split(" ")
            netGauge.rxKb = parseInt(parts[0]) || 0
            netGauge.txKb = parseInt(parts[1]) || 0
        }}
    }
    Process {
        id: uptimeProc
        command: ["bash", "-lc", "uptime -p | sed 's/up //'"]
        running: true
        stdout: SplitParser { onRead: data => infoBar.uptime = data.trim() }
    }
    Process {
        id: osAgeProc
        command: ["bash", "-lc",
            "birth=$(stat -c %W / 2>/dev/null); now=$(date +%s); diff=$((now-birth)); echo \"$((diff/86400))d\""]
        running: true
        stdout: SplitParser { onRead: data => infoBar.osAge = data.trim() }
    }

    // ── Refresh timers ────────────────────────────────────────────

    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: {
            cpuTempProc.running  = false; cpuTempProc.running  = true
            cpuUsageProc.running = false; cpuUsageProc.running = true
            gpuTempProc.running  = false; gpuTempProc.running  = true
            gpuUsageProc.running = false; gpuUsageProc.running = true
            ramUsageProc.running = false; ramUsageProc.running = true
            ramDetailProc.running= false; ramDetailProc.running= true
            netProc.running      = false; netProc.running      = true
        }
    }
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: {
            uptimeProc.running = false; uptimeProc.running = true
            osAgeProc.running  = false; osAgeProc.running  = true
        }
    }

    // ── Header ────────────────────────────────────────────────────

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: "SYSTEM"
        color: Qt.rgba(1, 1, 1, 0.35)
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
            }

            // Download track (left half: 180°→360°, i.e. startAngle=180, sweep=180)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: Qt.rgba(1,1,1,0.08); strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: 180; sweepAngle: 175 }
                }
            }
            // Upload track (right half: 0°→180°)
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: Qt.rgba(1,1,1,0.08); strokeWidth: 8
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
                    Layout.alignment: Qt.AlignHCenter
                    text: "NET"
                    color: Qt.rgba(1,1,1,0.4)
                    font.pixelSize: 11; font.letterSpacing: 2; font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "↓ " + (netGauge.rxKb >= 1024 ? (netGauge.rxKb/1024).toFixed(1)+"M" : netGauge.rxKb+"K")
                    color: "#52e0a0"
                    font.pixelSize: 12; font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "↑ " + (netGauge.txKb >= 1024 ? (netGauge.txKb/1024).toFixed(1)+"M" : netGauge.txKb+"K")
                    color: "#e05252"
                    font.pixelSize: 12; font.bold: true
                }
            }
        }
    }

    // ── Info bar (uptime + OS age) ────────────────────────────────

    Rectangle {
        id: infoBar
        Layout.fillWidth: true
        height: 42
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.05)

        property string uptime: "—"
        property string osAge: "—"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            // Uptime
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "󰔚 " + infoBar.uptime
                    color: Qt.rgba(1,1,1,0.75)
                    font.pixelSize: 14; font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: "uptime"
                    color: Qt.rgba(1,1,1,0.3)
                    font.pixelSize: 12; font.letterSpacing: 1
                }
            }

            Rectangle { width: 1; Layout.fillHeight: true; color: Qt.rgba(1,1,1,0.1); Layout.topMargin: 3; Layout.bottomMargin: 3 }

            // OS age
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "󰅐 " + infoBar.osAge
                    color: Qt.rgba(1,1,1,0.75)
                    font.pixelSize: 14; font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "os age"
                    color: Qt.rgba(1,1,1,0.3)
                    font.pixelSize: 12; font.letterSpacing: 1
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
        }

        // Shapes fill the Item exactly — center (65,65), outer r=50, inner r=36
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: Qt.rgba(1,1,1,0.08); strokeWidth: 8
                fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 65; centerY: 65; radiusX: 50; radiusY: 50; startAngle: -225; sweepAngle: 270 }
            }
        }
        Shape {
            visible: !gauge.singleRing
            anchors.fill: parent
            ShapePath {
                strokeColor: Qt.rgba(1,1,1,0.08); strokeWidth: 7
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
                color: Qt.rgba(1,1,1,0.4)
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
                color: gauge.singleRing ? Qt.rgba(1,1,1,0.5) : gauge.secondaryColor
                font.pixelSize: gauge.singleRing ? 11 : 12
                font.bold: !gauge.singleRing
            }
        }
    }
}
