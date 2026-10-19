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

    // while edited live the surface covers the screen (a dragged module can go
    // anywhere, the toolbar hangs below); only the bar + toolbar take input then
    readonly property bool editing: EditMode.target === "bar" && EditMode.screen === (screen?.name ?? "")
    implicitHeight: editing ? Math.max(50, (screen?.height ?? 1440) - 20) : 50
    exclusiveZone: 50
    mask: editing ? editRegion : null
    property Region editRegion: Region {
        item: barContent
        Region { item: editToolbar }
    }
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

    // Everything on the bar lives in here, so this one HoverHandler sees the
    // pointer over the background *and* over every button on top of it
    // (bar popups stay open while the pointer is anywhere on the bar).
    Item {
        id: barContent
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 50

        HoverHandler {
            onHoveredChanged: BarState.setBarHovered(bar.screen?.name ?? "", hovered)
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

            // long-press an empty spot of the bar: edit it live (BarEditLayer)
            TapHandler {
                onLongPressed: EditMode.start("bar", bar.screen?.name ?? "")
            }

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

    BarEditToolbar {
        id: editToolbar
        editor: editLayer
        anchors.horizontalCenter: parent.horizontalCenter
        y: barContent.height + 8
    }

    // drag ghost of the live editor: above everything, not clipped to the bar
    Item {
        id: overlay
        anchors.fill: parent
        z: 100
    }
}