import Quickshell
import QtQuick
import qs.services
import qs.components

BarButton {
    text: "⏻"
    onClicked: Quickshell.execDetached(["wlogout"])
}
