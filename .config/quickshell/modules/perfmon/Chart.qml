import QtQuick
import qs.services

// Line chart of recent values: series [{ values: [...], color, fill }],
// fixed range (min / max) or auto (max: -1). Newest value on the right.
Item {
    id: root
    property var series: []
    property real min: 0
    property real max: 100
    property int length: 90
    property string unit: ""
    onSeriesChanged: canvas.requestPaint()

    readonly property real topValue: {
        if (max > 0) return max
        let m = 1
        for (const s of series) for (const v of s.values) if (v > m) m = v
        return m * 1.15
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            ctx.strokeStyle = Colors.fade(0.06)
            ctx.lineWidth = 1
            for (let i = 1; i < 4; i++) { const y = Math.round(h * i / 4) + 0.5; ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke() }
            const span = root.topValue - root.min
            for (const s of root.series) {
                const vals = s.values.filter(v => v >= 0)
                if (vals.length < 2) continue
                const n = s.values.length
                const x = i => w - (n - 1 - i) * (w / (root.length - 1))
                const y = v => h - Math.max(0, Math.min(1, (v - root.min) / span)) * (h - 4) - 2
                ctx.beginPath()
                let started = false
                for (let i = 0; i < n; i++) {
                    if (s.values[i] < 0) continue
                    if (!started) { ctx.moveTo(x(i), y(s.values[i])); started = true } else ctx.lineTo(x(i), y(s.values[i]))
                }
                ctx.strokeStyle = s.color
                ctx.lineWidth = 2
                ctx.stroke()
                if (s.fill) {
                    ctx.lineTo(x(n - 1), h); ctx.lineTo(x(n - vals.length), h); ctx.closePath()
                    const g = ctx.createLinearGradient(0, 0, 0, h)
                    g.addColorStop(0, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.25))
                    g.addColorStop(1, Qt.rgba(s.color.r, s.color.g, s.color.b, 0))
                    ctx.fillStyle = g
                    ctx.fill()
                }
            }
        }
    }
    Text {
        anchors { right: parent.right; top: parent.top; margins: 2 }
        text: Math.round(root.topValue) + root.unit
        color: Colors.fade(0.3)
        font.pixelSize: 10
        font.family: Properties.fontFamily
    }
}
