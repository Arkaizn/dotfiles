import QtQuick
import QtQuick.Controls
import qs.services
import qs.components
import "."

// Small square icon button used in the wallpaper selector's header/toolbar.
// Local copy of the shared IconButton, kept in this directory and renamed
// so the wallpaper selector doesn't depend on qs.components.
//
// Usage:
//   WallpaperButton {
//       icon: "⟳"
//       tooltip: "Rescan wallpapers"
//       onClicked: doThing()
//   }
//
// Set `interactive: false` to keep the icon visible (e.g. as a static
// state indicator like an expand/collapse chevron) while disabling clicks
// and hover feedback.
Item {
    id: root
    property string icon: ""
    property string tooltip: ""
    property bool interactive: true
    signal clicked()

    implicitWidth: Properties.buttonHeight
    implicitHeight: Properties.buttonHeight

    // Background + icon live in one Item so they scale together on hover,
    // while root keeps a fixed hit-target size for the MouseArea/layout.
    Item {
        id: content
        anchors.fill: parent
        scale: mouseArea.containsMouse && root.interactive ? 1.12 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: Properties.radius
            color: Qt.rgba(0, 0, 0, 0.18)
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, mouseArea.containsMouse && root.interactive ? 0.28 : 0.18)
            opacity: root.interactive ? 1.0 : 0.6
            gradient: ButtonGradient {
                hovered: mouseArea.containsMouse && root.interactive
            }
            Behavior on border.color { ColorAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: Properties.color
            font.pixelSize: 13
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.interactive
        onClicked: root.clicked()
    }

    ToolTip.visible: root.tooltip.length > 0 && mouseArea.containsMouse && root.interactive
    ToolTip.text: root.tooltip
    ToolTip.delay: 400
}
