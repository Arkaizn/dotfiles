// qs/services/ButtonGradient.qml
import QtQuick

Gradient {
    property bool hovered: false

    GradientStop {
        position: 0.0
        color: hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.25)
    }
    GradientStop {
        position: 1.0
        color: Qt.rgba(1, 1, 1, 0.15)
    }
}