import QtQuick
import QtQuick.Layouts
import qs.services

// Section of the network page: small title (with optional controls on the
// right of it) above a dark card holding rows (SettingRow).
//   Section { title: "DNS"; SettingRow { first: true; … } SettingRow { … } }
ColumnLayout {
    id: root
    property string title: ""
    property string icon: ""
    property alias header: headerSlot.data   // extra items right of the title
    default property alias rows: body.data
    property color tint: "transparent"       // e.g. a highlighted card

    spacing: Tokens.space.s8

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space.s6
        visible: root.title !== ""
        spacing: 7
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: Colors.accent
            font.pixelSize: Tokens.font.body
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Colors.fade(0.55)
            font.pixelSize: Tokens.font.small
            font.bold: true
            font.family: Properties.fontFamily
            elide: Text.ElideRight          // the buttons on the right keep their size
        }
        RowLayout { id: headerSlot; spacing: Tokens.space.s6 }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight
        radius: Tokens.radius.card
        color: root.tint.a > 0 ? root.tint : Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        Behavior on color { ColorAnimation { duration: Anim.normal } }

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
