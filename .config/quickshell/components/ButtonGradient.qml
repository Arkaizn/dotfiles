// qs/services/ButtonGradient.qml
import QtQuick

Gradient {
    property bool hovered: false

    GradientStop { position: 0.0; color: hovered ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0.5, 0.5, 0.5, 0.45) }
    GradientStop { position: 1.0 ;color: hovered ? Qt.rgba(0.6, 0.6, 0.6, 0.2) : Qt.rgba(0.2, 0.2, 0.2, 0.2) }
}