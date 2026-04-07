// qs/services/ButtonBackground.qml
import QtQuick
import qs.services

Item {
    id: root

    // Properties to pass in from the parent, setting here just that they exist
    property bool hovered: false
    property string iconText: ""
    property int iconSize: 16
    property color color: bar.textColorIfHovered

    // Item doesnt have implicit size so we use the text implicitwidth
    implicitWidth: text.implicitWidth
    implicitHeight: text.implicitHeight

    anchors.fill: parent
    anchors.margins: 0.8
    anchors.topMargin: 1.5


    Rectangle {
        anchors.fill: parent
        radius: bar.radius
        color: Qt.rgba(0, 0, 0, 0.18)
        

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
