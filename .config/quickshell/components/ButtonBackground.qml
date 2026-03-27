import QtQuick
import qs.services

Item {
    id: root

    // Properties to pass in from the parent, seting here just that tehy exist
    property bool hovered: false
    property string iconText: ""
    property int iconSize: 16

    // Item doesnt have implicit size so we use the text implicitwidth
    implicitWidth: text.implicitWidth
    implicitHeight: text.implicitHeight

    anchors.fill: parent
    anchors.margins: 1

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconText
            font.pixelSize: root.iconSize
            color: root.hovered ? Colors.color6 : Colors.foreground
        }
    }
}
