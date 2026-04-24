import QtQuick
import QtQuick.Shapes

Item {
    id: root
    width: radius
    height: radius

    property real radius: 12
    property color color: "white"
    property string corner: "topLeft"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"

            startX: root.corner === "topLeft" || root.corner === "bottomLeft" ? 0 : root.radius
            startY: root.corner === "topLeft" || root.corner === "topRight" ? 0 : root.radius

            // Line to the arc start, arc, then close back
            PathAngleArc {
                centerX: root.corner === "topRight" || root.corner === "bottomRight" ? 0 : root.radius
                centerY: root.corner === "bottomLeft" || root.corner === "bottomRight" ? 0 : root.radius
                radiusX: root.radius
                radiusY: root.radius
                startAngle: ({"topLeft": 180, "topRight": 270, "bottomLeft": 90, "bottomRight": 0})[root.corner]
                sweepAngle: 90
            }

            PathLine {
                x: root.corner === "topLeft" || root.corner === "bottomLeft" ? 0 : root.radius
                y: root.corner === "topLeft" || root.corner === "topRight" ? 0 : root.radius
            }
        }
    }
}