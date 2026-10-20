import QtQuick
import qs.services

// History graph: a filled line over `values` (oldest first), 0..max
// (max 0 = the largest value shown). Redrawn when values change.
Canvas {
    id: root
    property var values: []
    property real max: 100
    property color color: Colors.color6
    implicitHeight: 34
    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const v = values, n = v.length
        if (n < 2) return
        const top = max > 0 ? max : Math.max(1, ...v)
        const step = width / (n - 1)
        const y = i => height - 1 - (height - 2) * Math.min(1, Math.max(0, v[i] / top))
        ctx.beginPath()
        ctx.moveTo(0, y(0))
        for (let i = 1; i < n; i++) ctx.lineTo(i * step, y(i))
        ctx.strokeStyle = root.color
        ctx.lineWidth = 1.5
        ctx.stroke()
        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
        ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.18)
        ctx.fill()
    }
}
