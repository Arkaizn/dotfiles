import QtQuick
import qs.services

// Round − / + badge on a part while editing a layout live (EditMode),
// like the corner badge on a wiggling app icon.
Rectangle {
    id: root
    property bool add: false            // + instead of −
    property string tooltip: ""
    signal clicked()

    width: 18
    height: 18
    radius: 9
    z: 50
    color: mouse.containsMouse ? (add ? Colors.accent : Colors.red) : Colors.surfacePopover
    border.width: 1
    border.color: Colors.line(0.35)
    scale: mouse.pressed ? 0.85 : mouse.containsMouse ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
    Behavior on color { ColorAnimation { duration: Anim.fast } }

    Text {
        font.family: Properties.fontFamily
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -0.5
        text: root.add ? "+" : "−"
        color: mouse.containsMouse ? Colors.background : Colors.ink
        font.pixelSize: Tokens.font.label
        font.bold: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
