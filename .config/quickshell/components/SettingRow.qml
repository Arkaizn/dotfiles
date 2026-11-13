import QtQuick
import QtQuick.Layouts
import qs.services

// Row inside a Section: label + description left, controls right, and a thin
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
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Tokens.space.s16; rightMargin: Tokens.space.s16 }
        height: 1
        color: Colors.fade(0.06)
    }

    GridLayout {
        anchors.fill: parent
        anchors.leftMargin: root.sub ? 30 : 16
        anchors.rightMargin: Tokens.space.s12
        anchors.topMargin: Tokens.space.s10
        anchors.bottomMargin: Tokens.space.s10
        columns: root.wide ? 1 : 2
        columnSpacing: Tokens.space.s12
        rowSpacing: Tokens.space.s10

        ColumnLayout {
            id: labels
            // takes what the controls leave (preferred ≈ 0 + fill): the controls
            // keep their size in a narrow window, long labels wrap instead
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 60
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.space.s2
            visible: root.label !== ""
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s6
                Text {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    wrapMode: Text.Wrap
                    text: root.label
                    color: Colors.ink
                    font.pixelSize: Tokens.font.body
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Colors.accent
                    opacity: root.changed ? 1 : 0
                    scale: root.changed ? 1 : 0.2
                    Behavior on opacity { NumberAnimation { duration: Anim.normal } }
                    Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.pop } }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.desc
                color: root.descError ? Colors.red : Colors.textMuted
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: slot
            Layout.alignment: root.wide ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            Layout.fillWidth: root.wide
            spacing: Tokens.space.s8
        }
    }
}
