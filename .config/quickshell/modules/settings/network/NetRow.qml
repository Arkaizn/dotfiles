import QtQuick
import QtQuick.Layouts
import qs.services

// Row inside a NetCard: label + description left, controls right, and a thin
// divider above it unless it's the first row. `changed` shows the same dot as
// changed settings elsewhere; `wide` puts the controls below the label.
Item {
    id: root
    property string label: ""
    property string desc: ""
    property bool first: false
    property bool changed: false
    property bool wide: false
    property bool sub: false              // option of the row above (indented)
    property bool descError: false        // desc is an error message (red)
    default property alias content: slot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(52, (wide ? labels.implicitHeight + slot.implicitHeight + 10 : Math.max(labels.implicitHeight, slot.implicitHeight)) + 20)

    Rectangle {
        visible: !root.first
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
        height: 1
        color: Colors.fade(0.06)
    }

    GridLayout {
        anchors.fill: parent
        anchors.leftMargin: root.sub ? 30 : 16
        anchors.rightMargin: 12
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        columns: root.wide ? 1 : 2
        columnSpacing: 12
        rowSpacing: 10

        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            visible: root.label !== ""
            RowLayout {
                spacing: 6
                Text {
                    text: root.label
                    color: Colors.ink
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Colors.color6
                    opacity: root.changed ? 1 : 0
                    scale: root.changed ? 1 : 0.2
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.desc
                color: root.descError ? Colors.red : Colors.fade(0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: slot
            Layout.alignment: root.wide ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            Layout.fillWidth: root.wide
            spacing: 8
        }
    }
}
