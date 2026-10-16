import QtQuick
import QtQuick.Layouts
import qs.services

// Settings row with free content: label + description left, children right.
// Same look as SettingItem, for pages that aren't driven by a spec.
Item {
    id: root

    property string label: ""
    property string desc: ""
    default property alias content: slot.data

    implicitHeight: Math.max(52, row.implicitHeight + 18)
    Behavior on opacity { NumberAnimation { duration: 150 } }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: root.label
                color: "white"
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.desc
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: slot
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 8
        }
    }
}
