import QtQuick
import QtQuick.Layouts
import qs.services

// One line of the properties dialog: a label, a value (hidden when the value is "").
//   PropRow { label: "Size"; value: "4 MB" }
RowLayout {
    id: row
    property string label
    property string value
    visible: value !== ""
    Layout.fillWidth: true
    spacing: Tokens.space.s12
    Text { Layout.preferredWidth: Tokens.size.row * 2.6; text: row.label; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
    Text { Layout.fillWidth: true; text: row.value; color: Colors.fade(0.88); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
           elide: Text.ElideMiddle; textFormat: Text.PlainText }
}
