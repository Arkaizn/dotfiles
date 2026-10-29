import QtQuick
import qs.services
import qs.services.lib

// Round avatar with the sender's initials, colored from the address.
Rectangle {
    id: root
    property var person: null            // { name, email }
    property int size: 34
    readonly property color tint: MailStore.palette[MailUtil.hue(person?.email ?? "")]

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.2)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.45)

    Text {
        anchors.centerIn: parent
        text: MailUtil.initials(root.person)
        color: root.tint
        font.pixelSize: Math.round(root.size * 0.38)
        font.bold: true
        font.family: Properties.fontFamily
    }
}
