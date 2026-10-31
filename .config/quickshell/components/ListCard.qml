import QtQuick
import QtQuick.Layouts
import qs.services

// A card holding a column of rows (SettingRow, PlainRow, Divider …), as wide
// as its layout. Section = this plus a title.
//   ListCard { SettingRow { first: true; … } SettingRow { … } }
Rectangle {
    default property alias content: col.data
    property color tint: "transparent"       // e.g. a highlighted card
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight
    radius: Tokens.radius.card
    color: tint.a > 0 ? tint : Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    Behavior on color { ColorAnimation { duration: Anim.normal } }
    ColumnLayout {
        id: col
        width: parent.width
        spacing: 0
    }
}
