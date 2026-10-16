import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Sidebar entry: icon + label, gradient when selected/hovered, and a small
// counter of changed values on the right.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property bool selected: false
    property int changes: 0
    signal clicked()

    implicitHeight: Properties.buttonHeight + 4
    scale: mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: Properties.radius + 2
        border.width: root.selected || mouse.containsMouse ? 1.5 : 0
        border.color: Qt.rgba(1, 1, 1, root.selected ? 0.24 : 0.14)
        gradient: ButtonGradient { hovered: root.selected }
        opacity: root.selected ? 1 : mouse.containsMouse ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.selected ? Colors.color6 : Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 16
            font.family: Properties.fontFamily
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.selected ? "white" : Qt.rgba(1, 1, 1, 0.75)
            font.pixelSize: 13
            font.bold: root.selected
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Rectangle {
            visible: root.changes > 0
            implicitWidth: Math.max(18, count.implicitWidth + 10)
            implicitHeight: 18
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.1)
            Text {
                id: count
                anchors.centerIn: parent
                text: root.changes
                color: Colors.color6
                font.pixelSize: 10
                font.bold: true
                font.family: Properties.fontFamily
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
