import QtQuick
import qs.services

// Line chart of recent samples, newest on the right.
//   series: [{ label, values, color, fill }]   values oldest first, < 0 = no reading (a gap)
//   span:   samples the full width stands for; until that many are collected
//           the ones there fill the width (the time label says how long that is)
//   min / max: fixed range; autoRange: fitted to the data, rounded to `step`
//   (zeroBased: from 0, for traffic; binary: steps in 1024s)
// Hovering shows the values at that point.
Item {
    id: root
    property var series: []
    property int span: 60
    property real interval: 1000            // ms per sample
    property real min: 0
    property real max: 100
    property bool autoRange: false
    property real step: 10
    property bool zeroBased: false
    property bool binary: false
    property var format: v => String(Math.round(v))
    property int gridLines: 4               // fixed / zero-based ranges; fitted ones get one per step
    property int gutter: 34                 // room for the value labels on the left

    readonly property int lines: range[2] ?? gridLines
    // samples shown: the longest series, at most `span`
    readonly property int count: series.reduce((m, s) => Math.max(m, Math.min(span, s.values.length)), 0)

    function niceCeil(v) {
        const base = binary ? Math.pow(1024, Math.max(0, Math.floor(Math.log(Math.max(1, v)) / Math.log(1024)))) : 1
        const x = v / base
        const mag = Math.pow(10, Math.floor(Math.log10(Math.max(1e-9, x))))
        for (const f of [1, 2, 2.5, 5, 10]) if (f * mag >= x) return f * mag * base
        return 10 * mag * base
    }
    readonly property var range: {
        if (!autoRange) return [min, max]
        let lo = Infinity, hi = -Infinity
        for (const s of series) {
            const v = s.values
            for (let i = Math.max(0, v.length - span); i < v.length; i++)
                if (v[i] >= 0) { if (v[i] < lo) lo = v[i]; if (v[i] > hi) hi = v[i] }
        }
        if (hi < lo) return [min, max]
        if (zeroBased) return [0, Math.max(max, niceCeil(hi * 1.1))]
        lo = Math.max(min, Math.floor((lo - step / 2) / step) * step)
        hi = Math.ceil((hi + step / 2) / step) * step
        // whole steps between grid lines: at most 6 lines, else double the step
        let n = Math.max(2, Math.round((hi - lo) / step)), st = step
        while (n > 6) { st *= 2; n = Math.ceil((hi - lo) / st) }
        return [lo, lo + n * st, n]
    }

    function ago(sec) {
        sec = Math.round(sec)
        if (sec < 60) return sec + " s"
        return Math.floor(sec / 60) + " min" + (sec % 60 ? " " + sec % 60 + " s" : "")
    }
    // value of series s at shown sample i (or -1)
    function valueAt(s, i) {
        const n = Math.min(span, s.values.length), j = i - (count - n)
        return j < 0 ? -1 : s.values[s.values.length - n + j]
    }

    property int hoverIndex: -1
    onSeriesChanged: canvas.requestPaint()
    onRangeChanged: canvas.requestPaint()
    onHoverIndexChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    readonly property real plotX: gutter
    readonly property real plotW: Math.max(1, width - gutter)
    readonly property real plotH: Math.max(1, height - 18)      // time labels below
    function xOf(i) { return plotX + (count < 2 ? plotW : plotW * i / (count - 1)) }

    // value labels
    Repeater {
        model: root.lines + 1
        Text {
            required property int index
            readonly property real v: root.range[0] + (root.range[1] - root.range[0]) * (root.lines - index) / root.lines
            x: 0
            width: root.gutter - 8
            y: Math.round(2 + (root.plotH - 4) * index / root.lines) - height / 2
            horizontalAlignment: Text.AlignRight
            text: root.format(v)
            color: Colors.fade(0.32)
            font.pixelSize: 10
            font.family: Properties.fontFamily
        }
    }
    // time labels
    Text {
        x: root.plotX
        y: root.plotH + 4
        text: root.count < 2 ? "" : "−" + root.ago((root.count - 1) * root.interval / 1000)
        color: Colors.fade(0.32)
        font.pixelSize: 10
        font.family: Properties.fontFamily
    }
    Text {
        anchors.right: parent.right
        y: root.plotH + 4
        text: "now"
        color: Colors.fade(0.32)
        font.pixelSize: 10
        font.family: Properties.fontFamily
    }
    Text {
        visible: root.count < 2
        x: root.plotX + (root.plotW - width) / 2
        y: (root.plotH - height) / 2
        text: "Collecting…"
        color: Colors.fade(0.3)
        font.pixelSize: 11
        font.family: Properties.fontFamily
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const X = root.plotX, W = root.plotW, H = root.plotH
            const lo = root.range[0], span = Math.max(1e-9, root.range[1] - lo)
            const y = v => 2 + (1 - Math.max(0, Math.min(1, (v - lo) / span))) * (H - 4)
            // grid
            ctx.lineWidth = 1
            for (let i = 0; i <= root.lines; i++) {
                const gy = Math.round(2 + (H - 4) * i / root.lines) + 0.5
                ctx.strokeStyle = Colors.fade(i === root.lines ? 0.10 : 0.05)
                ctx.beginPath(); ctx.moveTo(X, gy); ctx.lineTo(X + W, gy); ctx.stroke()
            }
            if (root.count < 2) return
            for (const s of root.series) {
                // runs of readings, split at gaps
                const runs = []
                let run = []
                for (let i = 0; i < root.count; i++) {
                    const v = root.valueAt(s, i)
                    if (v < 0) { if (run.length) runs.push(run); run = []; continue }
                    run.push([root.xOf(i), y(v)])
                }
                if (run.length) runs.push(run)
                for (const r of runs) {
                    ctx.beginPath()
                    ctx.moveTo(r[0][0], r[0][1])
                    for (let k = 1; k < r.length; k++) ctx.lineTo(r[k][0], r[k][1])
                    ctx.strokeStyle = s.color
                    ctx.lineWidth = 1.75
                    ctx.lineJoin = "round"
                    ctx.stroke()
                    if (s.fill && r.length > 1) {
                        ctx.lineTo(r[r.length - 1][0], H - 2); ctx.lineTo(r[0][0], H - 2); ctx.closePath()
                        const g = ctx.createLinearGradient(0, 0, 0, H)
                        g.addColorStop(0, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.20))
                        g.addColorStop(1, Qt.rgba(s.color.r, s.color.g, s.color.b, 0))
                        ctx.fillStyle = g
                        ctx.fill()
                    }
                }
            }
            // hover: line and dots
            if (root.hoverIndex >= 0) {
                const hx = Math.round(root.xOf(root.hoverIndex)) + 0.5
                ctx.strokeStyle = Colors.fade(0.25)
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(hx, 2); ctx.lineTo(hx, H - 2); ctx.stroke()
                for (const s of root.series) {
                    const v = root.valueAt(s, root.hoverIndex)
                    if (v < 0) continue
                    ctx.fillStyle = s.color
                    ctx.beginPath(); ctx.arc(hx, y(v), 3, 0, 2 * Math.PI); ctx.fill()
                }
            }
        }
    }

    MouseArea {
        id: hover
        x: root.plotX
        width: root.plotW
        height: root.plotH
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => root.hoverIndex = root.count < 2 ? -1 : Math.max(0, Math.min(root.count - 1, Math.round(mouse.x / width * (root.count - 1))))
        onExited: root.hoverIndex = -1
    }

    // values at the hovered point
    Rectangle {
        visible: root.hoverIndex >= 0
        readonly property real px: root.hoverIndex >= 0 ? root.xOf(root.hoverIndex) : 0
        x: px + 10 + width > root.width ? px - 10 - width : px + 10
        y: 4
        width: tip.implicitWidth + 16
        height: tip.implicitHeight + 10
        radius: Properties.radius
        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.96)
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        Column {
            id: tip
            anchors.centerIn: parent
            spacing: 2
            Text {
                text: root.hoverIndex < 0 ? "" : root.hoverIndex === root.count - 1 ? "now"
                    : "−" + root.ago((root.count - 1 - root.hoverIndex) * root.interval / 1000)
                color: Colors.fade(0.45)
                font.pixelSize: 10
                font.family: Properties.fontFamily
            }
            Repeater {
                model: root.hoverIndex >= 0 ? root.series : []
                Text {
                    required property var modelData
                    readonly property real v: root.valueAt(modelData, root.hoverIndex)
                    text: "<font color='" + modelData.color + "'>●</font> " + modelData.label + "  " + (v < 0 ? "–" : root.format(v))
                    textFormat: Text.StyledText
                    color: Colors.ink
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
        }
    }
}
