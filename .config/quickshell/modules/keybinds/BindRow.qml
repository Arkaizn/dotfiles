import QtQuick
import QtQuick.Layouts
import qs.services

// One shortcut: what it does on the left, its key combo(s) on the right
// (alternatives stacked). `bind` is a row from Keybinds.binds.
// Compact (narrow columns): several or long combos go below the text.
// `editable`: a pencil shows on hover → editRequested(the first raw bind).
Rectangle {
    id: row
    property var bind
    property bool compact: false
    property bool editable: false
    signal editRequested(var item)
    readonly property bool stacked: compact && (bind.combos.length > 1 || bind.combos.some(c => c.length > 2))
    implicitHeight: Math.max(compact ? 26 : 30, rowLayout.implicitHeight + 8)
    radius: 8
    color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
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
            color: Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: row.compact ? 11 : 12
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 4

            Text {
                visible: row.editable
                text: "󰏫"
                color: editMouse.containsMouse ? Colors.color6 : Qt.rgba(1, 1, 1, 0.6)
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
                    onClicked: row.editRequested(row.bind.items?.[0] ?? null)
                }
            }

            ColumnLayout {
                spacing: 4
                Repeater {
                    model: row.bind.combos
                    RowLayout {
                        required property var modelData
                        Layout.alignment: Qt.AlignRight
                        spacing: row.compact ? 3 : 4
                        Repeater {
                            model: modelData
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
