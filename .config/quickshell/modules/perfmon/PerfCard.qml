import QtQuick
import QtQuick.Layouts
import qs.services

// A card of the performance monitor: title (+ optional right text) above content.
Rectangle {
    id: root
    property string title
    property string icon: ""
    property string note: ""
    default property alias content: body.data

    radius: 14
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    implicitHeight: col.implicitHeight + 28

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 14 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Text { visible: root.icon !== ""; text: root.icon; color: Colors.color6; font.pixelSize: 14; font.family: Properties.fontFamily }
            Text { Layout.fillWidth: true; text: root.title; color: Colors.fade(0.75); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight }
            Text { text: root.note; color: Colors.fade(0.45); font.pixelSize: 11; font.family: Properties.fontFamily }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6 }
    }
}
