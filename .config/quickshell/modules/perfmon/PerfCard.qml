import QtQuick
import QtQuick.Layouts
import qs.services

// A card of the performance monitor: icon + title (+ dim note) and optional
// controls on the right (`actions`) above the content.
Rectangle {
    id: root
    property string title
    property string icon: ""
    property color iconColor: Colors.color6
    property string note: ""
    property int padding: 14
    default property alias content: body.data
    property alias actions: actionsRow.data

    radius: Math.max(6, Compositor.appRadius - 2)
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    implicitHeight: col.implicitHeight + 2 * padding

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: root.padding }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 22
            spacing: 8
            Text { visible: root.icon !== ""; text: root.icon; color: root.iconColor; font.pixelSize: 15; font.family: Properties.fontFamily }
            Text { text: root.title; color: Colors.ink; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight; Layout.maximumWidth: col.width * 0.6 }
            Text { Layout.fillWidth: true; text: root.note; color: Colors.fade(0.42); font.pixelSize: 11; font.family: Properties.fontFamily; elide: Text.ElideRight }
            RowLayout { id: actionsRow; spacing: 6 }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8 }
    }
}
