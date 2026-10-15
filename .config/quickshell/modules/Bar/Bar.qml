import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.services
import "."
import "../../components/outline.js" as Outline

PanelWindow {
    id: bar

    // for multiple Moniors
    required property var modelData
    screen: modelData

    // Top Bar
    anchors {
        top: true
        left: true
        right: true
    }
    
    // Space between edge of the screen and Bar
    margins.top: 10

    implicitHeight: 50
    exclusiveZone: height
    color: "transparent"
    aboveWindows: true

    // Popups attached under this bar (see BarPopup / BarState)
    readonly property var attached: BarState.forScreen(bar.screen?.name ?? "")
    readonly property bool squareLeft: attached.some(a => a.side === "left")
    readonly property bool squareRight: attached.some(a => a.side === "right")

    BackgroundEffect.blurRegion: Region {
        item: rectangle
        topLeftRadius: rectangle.topLeftRadius
        topRightRadius: rectangle.topRightRadius
        bottomRightRadius: rectangle.bottomRightRadius
        bottomLeftRadius: rectangle.bottomLeftRadius
    }

    Rectangle {
        id: rectangle
        anchors.fill: parent
        anchors.leftMargin: Properties.barInset
        anchors.rightMargin: Properties.barInset
        color: Properties.panelColor
        topLeftRadius: Properties.barRadius
        topRightRadius: Properties.barRadius
        // squared off where a popup hangs flush from that end
        bottomRightRadius: bar.squareRight ? 0 : Properties.barRadius
        bottomLeftRadius: bar.squareLeft ? 0 : Properties.barRadius
        Behavior on bottomRightRadius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // Border, with a gap wherever a popup is attached so the two
        // outlines join into one.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Properties.panelBorder
                strokeWidth: Properties.panelBorderWidth
                PathSvg {
                    path: Outline.bar(
                        rectangle.width, rectangle.height,
                        rectangle.topLeftRadius, rectangle.topRightRadius,
                        rectangle.bottomRightRadius, rectangle.bottomLeftRadius,
                        bar.attached.map(a => [a.x0 - Properties.barInset, a.x1 - Properties.barInset]),
                        Properties.panelBorderWidth / 2)
                }
            }
        }
    }

    // Call Bar Buttons
    Left {}
    Middle {}
    Right {}
}