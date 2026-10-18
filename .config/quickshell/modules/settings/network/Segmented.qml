import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Segmented control with a highlight that slides to the selected option.
//   Segmented { options: [{ label, value, icon? }]; value: x; onEdited: v => … }
Item {
    id: root
    property var options: []
    property var value
    property bool small: false
    signal edited(var value)

    readonly property int current: Math.max(0, options.findIndex(o => o.value === value))
    implicitWidth: row.implicitWidth + 6
    implicitHeight: small ? Properties.buttonHeight - 4 : Properties.buttonHeight

    Rectangle {
        anchors.fill: parent
        radius: Properties.radius + 2
        color: Colors.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.25)
        border.width: 1
        border.color: Colors.fade(0.08)
    }

    // the sliding highlight
    Rectangle {
        readonly property Item target: rep.count > root.current ? rep.itemAt(root.current) : null
        x: (target?.x ?? 0) + 3
        y: 3
        width: target?.width ?? 0
        height: parent.height - 6
        radius: Properties.radius
        visible: root.options.some(o => o.value === root.value)
        color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.22)
        border.width: 1
        border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.55)
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: row
        x: 3
        y: 3
        height: parent.height - 6
        spacing: 0
        Repeater {
            id: rep
            model: root.options
            Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool selected: index === root.current && root.options.some(o => o.value === root.value)
                implicitWidth: optRow.implicitWidth + (root.small ? 16 : 22)
                Layout.fillHeight: true

                RowLayout {
                    id: optRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        visible: (opt.modelData.icon ?? "") !== ""
                        text: opt.modelData.icon ?? ""
                        color: opt.selected ? Colors.color6 : Colors.fade(0.6)
                        font.pixelSize: 13
                        font.family: Properties.fontFamily
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    Text {
                        text: opt.modelData.label
                        color: opt.selected ? Colors.ink : Colors.fade(mouse.containsMouse ? 0.85 : 0.6)
                        font.pixelSize: root.small ? 11 : 12
                        font.bold: opt.selected
                        font.family: Properties.fontFamily
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!opt.selected) root.edited(opt.modelData.value)
                }
            }
        }
    }
}
