import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Button with icon + text in the ButtonBackground style.
// `primary` keeps the highlighted look (the main action of a bar).
Item {
    id: root

    property string icon: ""
    property string text: ""
    property bool primary: false
    property bool interactive: true
    property color textColor: "white"
    signal clicked()

    implicitWidth: row.implicitWidth + 26
    implicitHeight: Properties.buttonHeight
    opacity: interactive ? 1 : 0.4

    ButtonBackground {
        hovered: root.interactive && (root.primary || mouse.containsMouse)
        scale: !root.interactive ? 1
             : mouse.pressed ? Properties.onPressedButtonScale
             : mouse.containsMouse ? 1.04 : 1
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.primary ? Colors.color6 : root.textColor
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
