pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services

// A row on the password card: icon + the current choice; a click opens the
// list below it, a click on an entry picks it (user, session).
//
//   ChoicePicker { icon: "󰍹"; model: [...]; current: obj; label: o => o.name; onPicked: o => … }
ColumnLayout {
    id: root

    property string icon: ""
    property var model: []
    property var current: null
    property var label: o => String(o)
    property bool open: false
    signal picked(var choice)

    Layout.fillWidth: true
    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Properties.buttonHeight
        radius: Properties.radius + 2
        color: head.containsMouse || root.open ? Colors.fade(0.10) : Colors.fade(0.05)
        border.width: Properties.panelBorderWidth
        border.color: root.open ? Colors.fade(0.16) : Properties.cardBorder
        Behavior on color { ColorAnimation { duration: Anim.hover } }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: 12 }
            spacing: 10
            Text {
                text: root.icon
                color: Colors.fade(0.6)
                font.pixelSize: 15
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.current ? root.label(root.current) : ""
                color: Colors.ink
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            Text {
                visible: root.model.length > 1
                text: root.open ? "󰅃" : "󰅀"
                color: Colors.fade(0.5)
                font.pixelSize: 13
                font.family: Properties.fontFamily
            }
        }
        MouseArea {
            id: head
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.model.length > 1
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    // the list
    Repeater {
        model: root.open ? root.model : []
        Rectangle {
            id: entry
            required property var modelData
            // by label: the same entry read twice from a var list isn't the same object
            readonly property bool chosen: root.current !== null && root.label(modelData) === root.label(root.current)
            Layout.fillWidth: true
            Layout.leftMargin: 12
            implicitHeight: Properties.buttonHeight - 4
            radius: Properties.radius
            color: entryMouse.containsMouse ? Colors.fade(0.12) : chosen ? Colors.fade(0.07) : "transparent"
            Row {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    width: 14
                    text: entry.chosen ? "󰄬" : ""
                    color: Colors.ink
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                }
                Text {
                    text: root.label(entry.modelData)
                    color: entry.chosen ? Colors.ink : Colors.fade(0.75)
                    font.pixelSize: 12
                }
            }
            MouseArea {
                id: entryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // pick first: closing the list destroys this entry
                onClicked: { root.picked(entry.modelData); root.open = false }
            }
        }
    }
}
