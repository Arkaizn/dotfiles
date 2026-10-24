import QtQuick
import qs.services

// "Press any key" with a lock icon, pulsing; fades out when the password view
// opens. Position it with anchors (horizontalCenter, bottom).
Column {
    id: root

    property string text: "Press any key to unlock"
    property bool show: true            // the setting; hidden anyway while `auth`
    property bool auth: false

    spacing: 6
    opacity: auth || !show ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 250 } }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "󰌾"
        color: "white"
        font.pixelSize: 22
        font.family: Properties.fontFamily
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.text
        color: Qt.rgba(1, 1, 1, 0.7)
        font.pixelSize: 13
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
        }
    }
}
