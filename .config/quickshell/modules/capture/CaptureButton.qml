import QtQuick
import QtQuick.Layouts
import qs.services

// Big button of the capture menu: icon, label and its number key.
Rectangle {
    id: btn
    property string icon
    property string text
    property string key: ""
    property bool danger: false
    signal clicked()

    readonly property color tint: danger ? Colors.red : Colors.color6

    Layout.fillWidth: true
    implicitHeight: 74
    radius: 12
    scale: mouse.pressed ? 0.97 : 1
    color: mouse.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.18) : Colors.fade(0.05)
    border.width: 1
    border.color: mouse.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.6) : Colors.fade(0.08)
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: btn.icon
            color: btn.tint
            font.pixelSize: 24
            font.family: Properties.fontFamily
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: btn.text
            color: Colors.ink
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }
    }
    Text {
        visible: btn.key !== ""
        anchors { top: parent.top; right: parent.right; margins: 7 }
        text: btn.key
        color: Colors.fade(0.35)
        font.pixelSize: 10
        font.family: Properties.fontFamily
    }
}
