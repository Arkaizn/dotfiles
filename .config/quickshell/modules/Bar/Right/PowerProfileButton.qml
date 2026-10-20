import QtQuick
import qs.services
import qs.components

// Power profile (services/Power.qml): click cycles power saver → balanced →
// performance. Hidden without power-profiles-daemon.
BarButton {
    id: root
    visible: Power.available.length > 0
    text: (Power.icons[Power.current] ?? "󰗑") + (root.hovered ? " " + Power.labels[Power.current] : "")
    onClicked: Power.cycle()
}
