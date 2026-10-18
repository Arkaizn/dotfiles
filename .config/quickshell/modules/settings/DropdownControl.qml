import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../controlcenter"

// Button that opens a list to pick from.
//   options: [{ label, value, hint?, color? }]   value: the selected value
//   (color: a dot in front, e.g. the calendar's color)
Item {
    id: root

    property var options: []
    property var value
    signal edited(var value)

    readonly property var current: options.find(o => o.value === value)

    implicitWidth: 200
    implicitHeight: Properties.buttonHeight

    // grows at most 4px per side (it can be wide), like ActionButton
    scale: mouse.pressed ? Properties.onPressedButtonScale
         : mouse.containsMouse ? 1 + Math.min((Properties.onEnteredButtonScale - 1) * 0.4, 8 / Math.max(1, width)) : 1
    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    ButtonBackground {
        hovered: mouse.containsMouse || list.visible
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 8
        Rectangle {
            visible: !!root.current?.color
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            radius: 5
            color: root.current?.color ?? "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Text {
            Layout.fillWidth: true
            text: root.current?.label ?? "—"
            color: Colors.ink
            font.pixelSize: 12
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Chevron { open: list.visible }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: list.visible ? list.close() : list.open()
    }

    Popup {
        id: list
        y: root.height + 4
        width: Math.max(root.width, 160)
        height: Math.min(view.contentHeight + 12, 260)
        padding: 6
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape   // the button itself toggles it
        onOpened: view.positionViewAtIndex(Math.max(0, root.options.indexOf(root.current)), ListView.Center)

        background: Rectangle {
            radius: Properties.radius + 2
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            model: root.options
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: entry
                required property var modelData
                readonly property bool selected: modelData.value === root.value
                width: ListView.view.width
                height: 28
                radius: Properties.radius
                color: hover.hovered ? Colors.fade(0.08) : selected ? Colors.fade(0.05) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Rectangle {
                        visible: !!entry.modelData.color
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: entry.modelData.color ?? "transparent"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: entry.modelData.label
                        color: entry.selected ? Colors.color6 : Colors.ink
                        font.pixelSize: 12
                        font.bold: entry.selected
                        font.family: Properties.fontFamily
                    }
                    Text {
                        visible: text !== ""
                        text: entry.modelData.hint ?? ""
                        color: Colors.fade(0.4)
                        font.pixelSize: 10
                        font.family: Properties.fontFamily
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        list.close()
                        if (!entry.selected) root.edited(entry.modelData.value)
                    }
                }
            }
        }
    }
}
