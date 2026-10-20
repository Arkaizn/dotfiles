import QtQuick
import qs.services
import qs.components

// One number on the bar (CPU / GPU / memory / temperatures), from SysStats.
// Hidden while the value is unknown (-1), e.g. no NVIDIA GPU.
BarButton {
    id: root
    visible: value >= 0

    property string icon
    property int value: -1
    property string suffix: "%"

    Component.onCompleted: SysStats.acquire()
    Component.onDestruction: SysStats.release()

    text: root.icon + "  " + root.value + root.suffix
    iconSize: Properties.pixelSize
    cursorShape: Qt.ArrowCursor

    // its own gradient under the button's (the chips' slightly denser look)
    Rectangle {
        z: -1
        anchors.fill: parent
        radius: Properties.buttonradius
        gradient: ButtonGradient {
            hovered: root.hovered
        }
    }
}
