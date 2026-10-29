import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Segmented buttons for a fixed list of options.
// navStyle (calendar views): plain words, no button look; the current one is
// underlined and the line slides over to the one picked next.
Item {
    id: root

    property var options: []
    property string value: ""
    property bool navStyle: false
    signal edited(string value)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: root.navStyle ? 2 : 4

        Repeater {
            id: rep
            model: root.options
            Item {
                id: opt
                required property string modelData
                required property int index
                readonly property bool selected: modelData === root.value
                readonly property bool idle: root.navStyle && selected
                implicitWidth: label.implicitWidth + (root.navStyle ? 18 : 22)
                implicitHeight: Properties.buttonHeight

                scale: idle ? 1 : mouse.pressed ? Properties.onPressedButtonScale
                     : mouse.containsMouse && !root.navStyle ? Properties.onEnteredButtonScale : 1
                z: mouse.containsMouse ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

                ButtonBackground {
                    visible: !root.navStyle
                    hovered: opt.selected || mouse.containsMouse
                }
                // navStyle: a soft hover tint instead of a button
                Rectangle {
                    visible: root.navStyle
                    anchors.fill: parent
                    radius: Properties.radius
                    color: Colors.fade(0.06)
                    opacity: mouse.containsMouse && !opt.selected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Properties.bDuration } }
                }
                Text {
                    id: label
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.navStyle ? -1 : 0
                    text: opt.modelData
                    color: root.navStyle ? (opt.selected || mouse.containsMouse ? Colors.ink : Colors.fade(0.6))
                                         : (opt.selected ? Colors.ink : Colors.fade(0.55))
                    font.pixelSize: root.navStyle ? 13 : 12
                    font.bold: opt.selected
                    font.family: Properties.fontFamily
                    Behavior on color { ColorAnimation { duration: Properties.bDuration } }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: !opt.idle
                    cursorShape: opt.idle ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: root.edited(opt.modelData)
                }
            }
        }
    }

    // the line under the current option, sliding between them
    Rectangle {
        id: line
        visible: root.navStyle && target !== null
        readonly property Item target: {
            const i = root.options.indexOf(root.value)
            return i >= 0 && rep.count > i ? rep.itemAt(i) : null
        }
        readonly property real lineW: target ? Math.max(12, target.implicitWidth - 18) : 0
        x: target ? row.x + target.x + (target.width - lineW) / 2 : 0
        width: lineW
        y: root.height - 4
        height: 2
        radius: 1
        color: Colors.color6
        Behavior on x { enabled: line.visible; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: line.visible; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }
}
