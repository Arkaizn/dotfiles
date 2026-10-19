import QtQuick
import qs.services

// Follows the pointer while a chip is dragged on a layout page.
// `info` = { icon, name } of the dragged item.
Rectangle {
    id: ghost
    property string modId: ""
    property var info: ({ icon: "", name: "" })
    property bool active: false
    z: 100
    visible: active
    width: gRow.implicitWidth + 20
    height: 34
    radius: 9
    color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.30)
    border.width: 1
    border.color: Colors.color6
    Drag.active: active
    Drag.keys: ["barmod"]
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Row {
        id: gRow
        anchors.centerIn: parent
        spacing: 7
        Text { text: ghost.info.icon; color: Colors.ink; font.pixelSize: 14; font.family: Properties.fontFamily }
        Text { text: ghost.info.name; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
    }
}
