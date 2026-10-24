import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.services
import qs.services.lib
import qs.components
import "."
import "../../components/outline.js" as Outline

// The bar, on the screen edge set in Settings → Panel editor (PanelGeometry:
// top / bottom / left / right, thickness). Laid out "canonically" like a top
// bar — u along it, v from the screen edge inwards — and mapped to its real
// edge with EdgeMap (the outline as a matrix; content is only moved).
PanelWindow {
    id: bar

    // for multiple Moniors
    required property var modelData
    screen: modelData

    readonly property string edge: PanelGeometry.barEdge
    readonly property bool vertical: EdgeMap.vertical(edge)
    anchors {
        top: EdgeMap.anchors(edge).top
        bottom: EdgeMap.anchors(edge).bottom
        left: EdgeMap.anchors(edge).left
        right: EdgeMap.anchors(edge).right
    }
    // space between the screen edge and the bar
    margins {
        top: edge === "top" ? PanelGeometry.barGap : 0
        bottom: edge === "bottom" ? PanelGeometry.barGap : 0
        left: edge === "left" ? PanelGeometry.barGap : 0
        right: edge === "right" ? PanelGeometry.barGap : 0
    }

    // while edited live the surface covers the screen (a dragged module can go
    // anywhere, the toolbar hangs beside it); only the bar + toolbar take input then
    readonly property bool editing: EditMode.target === "bar" && EditMode.screen === (screen?.name ?? "")
    // Settings → Panel editor; while its grip is dragged the bar shows liveThickness,
    // the exclusive zone (windows move) only follows on release
    readonly property int thickness: liveThickness > 0 ? liveThickness : PanelGeometry.barThickness
    property int liveThickness: 0
    // the surface across the edge (its depth): the bar, or nearly the screen while editing
    readonly property int depth: editing ? Math.max(thickness, EdgeMap.across(edge, screen?.width ?? 2560, screen?.height ?? 1440) - 20) : thickness
    implicitHeight: vertical ? 0 : depth
    implicitWidth: vertical ? depth : 0
    exclusiveZone: PanelGeometry.barThickness
    mask: editing ? editRegion : null
    property Region editRegion: Region {
        item: barContent
        Region { item: editToolbar }
        Region { item: thicknessGrip }
    }
    color: "transparent"
    aboveWindows: true

    // the surface along the edge
    readonly property real alongLen: vertical ? height : width

    // Popups attached to this bar (see BarPopup / BarState); side "left" / "right"
    // = flush with its start / end
    readonly property var attached: BarState.forScreen(bar.screen?.name ?? "")
    readonly property bool squareStart: attached.some(a => a.side === "left")
    readonly property bool squareEnd: attached.some(a => a.side === "right")

    BackgroundEffect.blurRegion: Region {
        item: rectangle
        topLeftRadius: rectangle.topLeftRadius
        topRightRadius: rectangle.topRightRadius
        bottomRightRadius: rectangle.bottomRightRadius
        bottomLeftRadius: rectangle.bottomLeftRadius
    }

    // Everything on the bar lives in here, so this one HoverHandler sees the
    // pointer over the background *and* over every button on top of it
    // (bar popups stay open while the pointer is anywhere on the bar).
    Item {
        id: barContent
        readonly property var r: EdgeMap.mapRect(bar.edge, bar.depth, 0, 0, bar.alongLen, bar.thickness)
        x: r.x
        y: r.y
        width: r.w
        height: r.h

        HoverHandler {
            onHoveredChanged: BarState.setBarHovered(bar.screen?.name ?? "", hovered)
        }

        Rectangle {
            id: rectangle
            anchors.fill: parent
            anchors.leftMargin: bar.vertical ? 0 : Properties.barInset
            anchors.rightMargin: bar.vertical ? 0 : Properties.barInset
            anchors.topMargin: bar.vertical ? Properties.barInset : 0
            anchors.bottomMargin: bar.vertical ? Properties.barInset : 0
            color: Properties.panelColor
            // the side facing the screen is squared off where a popup hangs flush from that end
            property real innerStart: bar.squareStart ? 0 : Properties.barRadius
            property real innerEnd: bar.squareEnd ? 0 : Properties.barRadius
            Behavior on innerStart { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on innerEnd { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            readonly property var c: EdgeMap.corners(bar.edge, { outerStart: Properties.barRadius, outerEnd: Properties.barRadius,
                                                                  innerEnd: innerEnd, innerStart: innerStart })
            topLeftRadius: c.tl
            topRightRadius: c.tr
            bottomRightRadius: c.br
            bottomLeftRadius: c.bl

            // long-press an empty spot of the bar: edit it live (BarEditLayer)
            TapHandler {
                onLongPressed: EditMode.start("bar", bar.screen?.name ?? "")
            }

            // Border, with a gap wherever a popup is attached so the two
            // outlines join into one. Drawn canonically, mapped to the edge.
            Item {
                id: borderBox
                readonly property real len: bar.vertical ? rectangle.height : rectangle.width
                width: len
                height: bar.thickness
                transform: Matrix4x4 { matrix: EdgeMap.qmatrix(EdgeMap.matrix(bar.edge, bar.thickness)) }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Properties.panelBorder
                        strokeWidth: Properties.panelBorderWidth
                        PathSvg {
                            path: Outline.bar(
                                borderBox.len, bar.thickness,
                                Properties.barRadius, Properties.barRadius,
                                rectangle.innerEnd, rectangle.innerStart,
                                bar.attached.map(a => [a.x0 - Properties.barInset, a.x1 - Properties.barInset]),
                                Properties.panelBorderWidth / 2)
                        }
                    }
                }
            }
        }

        // Call Bar Buttons
        Left { id: leftSection; screenName: bar.screen?.name ?? ""; editing: bar.editing; dragId: editLayer.dragId }
        Middle { id: middle; screenName: bar.screen?.name ?? ""; editing: bar.editing; dragId: editLayer.dragId }
        Right { id: rightSection; screenName: bar.screen?.name ?? ""; editing: bar.editing; dragId: editLayer.dragId }

        BarEditLayer {
            id: editLayer
            anchors.fill: parent
            screenName: bar.screen?.name ?? ""
            sections: [leftSection, middle.centerLeftSection, middle.centerSection, middle.centerRightSection, rightSection]
            overlay: overlay
            toolbar: editToolbar
        }
    }

    // toolbar + thickness grip: on the bar's inner side, in the middle
    BarEditToolbar {
        id: editToolbar
        editor: editLayer
        readonly property var p: EdgeMap.mapRect(bar.edge, bar.depth, (bar.alongLen - (bar.vertical ? height : width)) / 2,
                                                 bar.thickness + 16, bar.vertical ? height : width, bar.vertical ? width : height)
        x: p.x
        y: p.y
    }

    ResizeHandle {
        id: thicknessGrip
        visible: bar.editing && editLayer.dragId === ""
        horizontal: bar.vertical
        sign: bar.edge === "bottom" || bar.edge === "right" ? -1 : 1
        readonly property var p: EdgeMap.mapRect(bar.edge, bar.depth, (bar.alongLen - (bar.vertical ? height : width)) / 2,
                                                 bar.thickness - 4, bar.vertical ? height : width, bar.vertical ? width : height)
        x: p.x
        y: p.y
        property real start: 0
        onStarted: start = bar.thickness
        onMoved: d => bar.liveThickness = Snap.resize(start, d, PanelGeometry.limits["bar.thickness"][0], PanelGeometry.limits["bar.thickness"][1], 2)
        onDone: { if (bar.liveThickness > 0) PanelGeometry.set("bar", "thickness", bar.liveThickness); bar.liveThickness = 0 }
    }

    // drag ghost of the live editor: above everything, not clipped to the bar
    Item {
        id: overlay
        anchors.fill: parent
        z: 100
    }
}
