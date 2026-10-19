import QtQuick
import QtQuick.Shapes
import qs.services

// Ring gauge in the dashboard's style: a faint disc with the card outline, a
// 270° arc filled to `value` of `max` in the component color, the number in
// the middle and a second line under it. The arc turns yellow / red past
// `warn` / `crit`.
Item {
    id: root
    property real value: -1
    property real min: 0
    property real max: 100
    property real warn: 75
    property real crit: 90
    property color color: Colors.color6
    property string text: value < 0 ? "–" : Math.round(value)
    property string unit: value < 0 ? "" : "%"
    property string sub: ""
    property int thickness: 8

    readonly property real frac: value < 0 ? 0 : Math.max(0, Math.min(1, (value - min) / (max - min)))
    readonly property color tint: value >= crit ? Colors.red : value >= warn ? Colors.yellow : color
    // no animation: values change every second, and animating them redraws the
    // whole window most of the time (measured: ~20% of a core vs ~1% without)

    implicitWidth: 116
    implicitHeight: 116

    readonly property real size: Math.min(width, height)
    readonly property real radius: size / 2 - thickness / 2 - 7

    Rectangle {
        anchors.centerIn: parent
        width: root.size
        height: width
        radius: width / 2
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.05)
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
    }
    // drawn by Shape on the GPU: a Canvas repainted every frame cost a lot of CPU
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Colors.fade(0.07)
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: 135; sweepAngle: 270 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.tint
            strokeWidth: root.frac > 0.001 ? root.thickness : 0
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: 135; sweepAngle: 270 * root.frac }
        }
    }
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -2
        spacing: 0
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 1
            Text { id: valueText; text: root.text; color: root.value < 0 ? Colors.fade(0.35) : Colors.ink; font.pixelSize: 24; font.bold: true; font.family: Properties.fontFamily }
            Text { anchors.baseline: valueText.baseline; text: root.unit; color: Colors.fade(0.5); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: root.sub
            color: Colors.fade(0.55)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
    }
}
