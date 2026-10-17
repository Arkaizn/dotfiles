import QtQuick
import QtQuick.Layouts
import qs.services

// Section of the network page: small title (with optional controls on the
// right of it) above a dark card holding rows (NetRow).
//   NetCard { title: "DNS"; NetRow { first: true; … } NetRow { … } }
ColumnLayout {
    id: root
    property string title: ""
    property string icon: ""
    property alias header: headerSlot.data   // extra items right of the title
    default property alias rows: body.data
    property color tint: "transparent"       // e.g. a highlighted card

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        visible: root.title !== ""
        spacing: 7
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: Colors.color6
            font.pixelSize: 13
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 12
            font.bold: true
            font.family: Properties.fontFamily
        }
        RowLayout { id: headerSlot; spacing: 6 }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight
        radius: 14
        color: root.tint.a > 0 ? root.tint : "#27000000"
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        Behavior on color { ColorAnimation { duration: 200 } }
        clip: true

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
