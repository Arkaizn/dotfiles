import Quickshell
import QtQuick
import qs.services
import qs.components

BarButton {
    id: notifBtn

    // bell with a slash while do-not-disturb is on
    text: Notifs.dnd ? Icons.get("dnd") : Icons.get("notifications")

    // Optional unread badge (on the button itself, so it doesn't scale with the background)
    Rectangle {
        Component.onCompleted: parent = notifBtn
        visible: Notifs.count > 0
        anchors { top: parent.top; right: parent.right; margins: 4 }
        width: 8; height: 8
        radius: 4
        color: "#ff5f5f"
    }

    buttons: Qt.LeftButton | Qt.RightButton
    // right click: do not disturb on / off
    onClicked: mouse => mouse.button === Qt.RightButton ? Notifs.setDnd(!Notifs.dndManual) : Panels.toggle("controlCenter", (QsWindow.window as QsWindow)?.screen)
}
