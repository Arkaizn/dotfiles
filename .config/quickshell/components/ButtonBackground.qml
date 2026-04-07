import QtQuick
import qs.services

Item {
    id: root

    // Properties to pass in from the parent, seting here just that tehy exist
    property bool hovered: false
    property string iconText: ""
    property int iconSize: 16
    property color color: root.hovered ? Colors.color6 : Colors.foreground

    // Item doesnt have implicit size so we use the text implicitwidth
    implicitWidth: text.implicitWidth
    implicitHeight: text.implicitHeight

    anchors.fill: parent
    anchors.topMargin: 2
    anchors.leftMargin: 1
    anchors.rightMargin: 1


    Rectangle {
        anchors.fill: parent
        radius: 7
        color: bar.buttonColorIfHovered
        

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconText
            font.pixelSize: root.iconSize
            color: root.color
        }
    }
}
