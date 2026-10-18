// qs/services/ButtonGradient.qml
import QtQuick
import qs.services

Gradient {
    property bool hovered: false

    // light mode: white glass instead of grey
    GradientStop { position: 0.0; color: Colors.light ? (hovered ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.75))
                                                     : (hovered ? Qt.rgba(0.7, 0.7, 0.7, 0.5) : Qt.rgba(0.5, 0.5, 0.5, 0.45)) }
    GradientStop { position: 1.0; color: Colors.light ? (hovered ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.45))
                                                     : (hovered ? Qt.rgba(0.4, 0.4, 0.4, 0.2) : Qt.rgba(0.2, 0.2, 0.2, 0.2)) }
}