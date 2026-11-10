import QtQuick
import qs.services

// A server's picture: its own choice, else what the scan saw (Proxmox, a Docker
// host, the distro; ServerStore.logoOf), else a plain server glyph. With `badge`
// the distro's logo sits small in the corner when the main one is something else.
//   ServerLogo { name: server.name; size: 30 }
Item {
    id: root

    property string name: ""
    property real size: 28
    property bool badge: true
    readonly property var logo: ServerStore.logoOf(name)

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        source: root.logo.main
        sourceSize: Qt.size(Math.round(root.size * 2), Math.round(root.size * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
    }
    Text {
        anchors.centerIn: parent
        visible: !img.visible
        text: "󰒋"
        color: Colors.textMuted
        font.pixelSize: root.size * 0.82
        font.family: Properties.fontFamily
    }
    Image {
        visible: root.badge && root.logo.os !== "" && status === Image.Ready
        source: root.logo.os
        width: Math.round(root.size * 0.46)
        height: width
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -3
        anchors.bottomMargin: -3
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
}
