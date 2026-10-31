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
    radius: Tokens.radius.lg
    color: Colors.fade(0.05)
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder

    // content stays compact and vertically centred when the tile is taller
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.s10 }
        spacing: Tokens.space.s2

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            Text {
                text: tile.icon
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.body
                font.family: Properties.fontFamily
            }
            Text {
                text: tile.label
                color: Colors.fade(0.35)
                font.pixelSize: Tokens.font.micro; font.letterSpacing: 1; font.bold: true
                Layout.fillWidth: true
            }
        }
        Text {
            text: tile.value
            color: Colors.fade(0.85)
            font.pixelSize: Tokens.font.subtitle; font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        // optional extra content (e.g. a bar) on its own row below the value
        Item {
            id: extraSlot
            visible: children.length > 0
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space.s6
            Layout.preferredHeight: childrenRect.height
        }
    }
}
