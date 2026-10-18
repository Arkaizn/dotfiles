import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Tile for Wi-Fi / Bluetooth / tools.
// expandable: the tile opens the detail list (expandClicked), the power
//             button on the right switches it on/off (toggled).
// otherwise:  the whole tile is one button (toggled), e.g. the tools.
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false       // on/off look (off = greyed out)
    property bool expanded: false     // detail list open
    property bool expandable: true

    signal toggled()
    signal expandClicked()

    implicitHeight: 56
    radius: 12
    border.width: 1.5
    border.color: Colors.fade(mouse.containsMouse || active ? 0.28 : 0.14)
    gradient: ButtonGradient { hovered: root.active || mouse.containsMouse }
    scale: mouse.pressed ? Properties.onPressedButtonScale : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expandable ? root.expandClicked() : root.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 10

        Text {
            text: root.icon
            color: root.active || !root.expandable ? Colors.ink : Colors.fade(0.4)
            font.pixelSize: 20
            Behavior on color { ColorAnimation { duration: 150 } }
            font.family: Properties.fontFamily
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.active || !root.expandable ? Colors.ink : Colors.fade(0.4)
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.subtitle
                color: Colors.fade(root.active || !root.expandable ? 0.55 : 0.3)
                Behavior on color { ColorAnimation { duration: 150 } }
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        Chevron {
            visible: root.expandable
            open: root.expanded
        }

        // on/off switch
        IconButton {
            visible: root.expandable
            implicitWidth: 28
            implicitHeight: 28
            icon: "󰐥"
            active: root.active
            textColor: root.active ? Colors.ink : Colors.fade(0.4)
            tooltip: root.active ? "Turn off" : "Turn on"
            onClicked: root.toggled()
        }
    }
}
