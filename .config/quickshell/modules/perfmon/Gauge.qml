import QtQuick
import QtQuick.Shapes
import qs.services

// Ring gauge (CAM style): a 270° arc filled to `value` of `max`, the number in
// the middle, a second line under it. Turns yellow / red past `warn` / `crit`.
Item {
    id: root
    property real value: -1
    property real min: 0
    property real max: 100
    property real warn: 75
    property real crit: 90
    property string text: value < 0 ? "–" : Math.round(value) + "%"
    property string sub: ""
    property int thickness: 12

    readonly property real frac: value < 0 ? 0 : Math.max(0, Math.min(1, (value - min) / (max - min)))
    readonly property color tint: value >= crit ? "#f38ba8" : value >= warn ? "#f9e2af" : Colors.color6
    // drawn by Shape on the GPU: a Canvas repainted every animation frame cost a lot of CPU
    property real shown: frac
    // no animation: values change every second, and animating them redraws the
    // whole window most of the time (measured: ~20% of a core vs ~1% without)

    implicitWidth: 150
    implicitHeight: 150

    readonly property real radius: Math.min(width, height) / 2 - thickness / 2 - 2
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.08)
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: 135; sweepAngle: 270 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.tint
            strokeWidth: root.shown > 0.001 ? root.thickness : 0
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: 135; sweepAngle: 270 * root.shown }
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.text; color: "white"; font.pixelSize: 26; font.bold: true; font.family: Properties.fontFamily }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.sub; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 12; font.family: Properties.fontFamily }
    }
}
