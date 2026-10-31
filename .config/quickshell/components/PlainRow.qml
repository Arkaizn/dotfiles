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
    Behavior on opacity { NumberAnimation { duration: Anim.normal } }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s16
        anchors.rightMargin: Tokens.space.s12
        spacing: Tokens.space.s12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s2
            Text {
                text: root.label
                color: Colors.ink
                font.pixelSize: Tokens.font.body
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.desc
                color: Colors.fade(0.5)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: slot
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: Tokens.space.s8
        }
    }
}
