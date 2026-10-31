// qs/services/ButtonGradient.qml
import QtQuick
import qs.services

Gradient {
    property bool hovered: false

    // light mode: white glass instead of grey
    GradientStop { position: 0.0; color: Colors.light ? (hovered ? Colors.neutral(1, 0.95) : Colors.neutral(1, 0.75))
                                                     : (hovered ? Colors.neutral(0.7, 0.5) : Colors.neutral(0.5, 0.45)) }
    GradientStop { position: 1.0; color: Colors.light ? (hovered ? Colors.neutral(1, 0.7) : Colors.neutral(1, 0.45))
                                                     : (hovered ? Colors.neutral(0.4, 0.2) : Colors.neutral(0.2, 0.2)) }
}