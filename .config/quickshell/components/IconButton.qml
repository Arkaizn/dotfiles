import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// Square icon button with the same look/feel as the bar buttons
// (ButtonBackground + hover/press scale).
//
//   IconButton {
//       icon: "󰑐"
//       tooltip: "Rescan"
//       active: false        // keeps the hovered look, e.g. the selected mode
//       interactive: true    // false = static indicator, no clicks/hover
//       onClicked: doThing()
//   }
// A trash / archive / star / junk icon gets its color (Icons.tint, Shell → Icons)
// unless textColor is set.
Item {
    id: root

    property string icon: ""
    property string tooltip: ""
    property bool active: false
    property bool interactive: true
    property int iconSize: 14
    property color textColor: Icons.tint(icon, Properties.color)
    signal clicked()

    implicitWidth: Properties.buttonHeight
    implicitHeight: Properties.buttonHeight
    // in a layout: never squeezed below its size (the texts next to it give way)
    Layout.minimumWidth: implicitWidth
    opacity: interactive ? 1.0 : 0.5

    ButtonBackground {
        id: buttonBackground
        hovered: root.active || (root.interactive && mouseArea.containsMouse)
        iconText: root.icon
        iconSize: root.iconSize
        textColor: root.textColor
        scale: !root.interactive ? Properties.onExitedButtonScale
             : mouseArea.pressed ? Properties.onPressedButtonScale
             : mouseArea.containsMouse ? Properties.onEnteredButtonScale
             : Properties.onExitedButtonScale
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: root.tooltip.length > 0 && mouseArea.containsMouse && root.interactive
    ToolTip.text: root.tooltip
    ToolTip.delay: 400
}
