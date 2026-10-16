import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Segmented buttons for a fixed list of options.
RowLayout {
    id: root

    property var options: []
    property string value: ""
    signal edited(string value)

    spacing: 4

    Repeater {
        model: root.options
        Item {
            id: opt
            required property string modelData
            readonly property bool selected: modelData === root.value
            implicitWidth: label.implicitWidth + 22
            implicitHeight: Properties.buttonHeight

            scale: mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? Properties.onEnteredButtonScale : 1
            z: mouse.containsMouse ? 1 : 0
            Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

            ButtonBackground {
                hovered: opt.selected || mouse.containsMouse
            }
            Text {
                id: label
                anchors.centerIn: parent
                text: opt.modelData
                color: opt.selected ? "white" : Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 12
                font.bold: opt.selected
                font.family: Properties.fontFamily
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.edited(opt.modelData)
            }
        }
    }
}
