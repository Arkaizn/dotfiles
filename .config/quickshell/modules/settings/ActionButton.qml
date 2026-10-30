import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Button with icon + text in the ButtonBackground style.
// `primary` keeps the highlighted look (the main action of a bar). A trash /
// archive / star / junk icon gets its color (Icons.tint).
Item {
    id: root

    property string icon: ""
    property string text: ""
    property bool primary: false
    property bool interactive: true
    property color textColor: Colors.ink
    signal clicked()

    implicitWidth: row.implicitWidth + 26
    implicitHeight: Properties.buttonHeight
    opacity: interactive ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    // the whole button scales (background and text together); wide buttons
    // grow at most 4px per side, so they stay inside the edges around them
    scale: !interactive ? 1
         : mouse.pressed ? Properties.onPressedButtonScale
         : mouse.containsMouse ? 1 + Math.min((Properties.onEnteredButtonScale - 1) * 0.4, 8 / Math.max(1, width)) : 1
    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    ButtonBackground {
        hovered: root.interactive && (root.primary || mouse.containsMouse)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.primary ? Colors.color6 : Icons.tint(root.icon, root.textColor)
            font.pixelSize: 14
            font.family: Properties.fontFamily
        }
        Text {
            text: root.text
            color: root.textColor
            font.pixelSize: 12
            font.bold: root.primary
            font.family: Properties.fontFamily
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
