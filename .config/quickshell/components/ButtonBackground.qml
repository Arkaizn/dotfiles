// qs/services/ButtonBackground.qml
import QtQuick
import qs.services

Item {
    id: root

    // Properties to pass in from the parent, setting here just that they exist
    property bool hovered: false
    property string iconText: ""
    property int iconSize: Properties.iconSize
    property color textColor: Properties.color
    property bool fontBold: Properties.fontBold
    property string fontFamily: Properties.fontFamily

    // Item doesnt have implicit size so we use the text implicitwidth
    implicitWidth: text.implicitWidth
    implicitHeight: text.implicitHeight
    anchors.fill: parent
    anchors.margins: 0
    
    Behavior on scale {
        NumberAnimation {
            duration: Anim.button
            easing.type: Anim.standard
        } 
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        color: Colors.light ? Colors.neutral(1, 0.35) : Colors.dim(0.18)
        border.color: Colors.fade(root.hovered ? 0.28 : 0.18)
        border.width: 1.5

        gradient: ButtonGradient {
            hovered: root.hovered
            }
        

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconText
            font.pixelSize: root.iconSize
            font.family: root.fontFamily
            font.bold: root.fontBold
            color: root.textColor
        }
    }
}
