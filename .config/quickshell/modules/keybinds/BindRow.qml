pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services

// One shortcut: what it does on the left, its key combo(s) on the right
// (alternatives stacked). `bind` is a row from Keybinds.binds.
// Compact (narrow columns): several or long combos go below the text.
// `editable`: a pencil per combo shows on hover → editRequested(that raw bind).
Rectangle {
    id: row
    property var bind
    property bool compact: false
    property bool editable: false
    signal editRequested(var item)
    readonly property bool stacked: compact && (bind.combos.length > 1 || bind.combos.some(c => c.length > 2))
    implicitHeight: Math.max(compact ? 26 : 30, rowLayout.implicitHeight + 8)
    radius: 8
    color: rowHover.hovered ? Colors.fade(0.05) : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    HoverHandler { id: rowHover }

    GridLayout {
        id: rowLayout
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 4 }
        columns: row.stacked ? 1 : 2
        columnSpacing: row.compact ? 6 : 10
        rowSpacing: 3

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 1          // wrap in the space left, don't push under the keys
            text: row.bind.desc
            color: Colors.fade(0.85)
            font.pixelSize: row.compact ? 11 : 12
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 4

            ColumnLayout {
                spacing: 4
                Repeater {
                    model: row.bind.combos
                    RowLayout {
                        id: comboRow
                        required property var modelData
                        required property int index
                        Layout.alignment: Qt.AlignRight
                        spacing: row.compact ? 3 : 4
                        // one pencil per combo: edits exactly that bind
                        Text {
                            visible: row.editable
                            text: "󰏫"
                            color: editMouse.containsMouse ? Colors.color6 : Colors.fade(0.6)
                            opacity: rowHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            font.pixelSize: 13
                            font.family: Properties.fontFamily
                            MouseArea {
                                id: editMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: row.editRequested(row.bind.items?.[comboRow.index] ?? null)
                            }
                        }
                        Repeater {
                            model: comboRow.modelData
                            Keycap {
                                required property string modelData
                                key: modelData
                                compact: row.compact
                            }
                        }
                    }
                }
            }
        }
    }
}
