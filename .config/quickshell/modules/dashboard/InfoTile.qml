import QtQuick
import QtQuick.Layouts
import qs.services

// Small labelled stat tile used in DashboardStats (uptime, OS age, disk).
// Children go below the value (e.g. a progress bar).
Rectangle {
    id: tile
    property string icon: ""
    property string value: "—"
    property string label: ""
    default property alias extra: extraSlot.data

    Layout.fillWidth: true
    Layout.fillHeight: true
    // never shrink below the content (text + optional bar)
    Layout.minimumHeight: col.implicitHeight + 20
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.05)
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder

    // content stays compact and vertically centred when the tile is taller
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: tile.icon
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 13
                font.family: Properties.fontFamily
            }
            Text {
                text: tile.label
                color: Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: 10; font.letterSpacing: 1; font.bold: true
                Layout.fillWidth: true
            }
        }
        Text {
            text: tile.value
            color: Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: 16; font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        // optional extra content (e.g. a bar) on its own row below the value
        Item {
            id: extraSlot
            visible: children.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: childrenRect.height
        }
    }
}
