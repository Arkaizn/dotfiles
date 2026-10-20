import QtQuick
import qs.services
import qs.components

// Opens the screenshot / recording menu (modules/capture).
BarButton {
    text: Icons.get("screenshot")
    onClicked: Panels.toggle("capture")
}
