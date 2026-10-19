import QtQuick
import qs.services

// Where a dragged part can be dropped while editing a layout live: a light
// pywal tint with a pywal border. Only shows while something is dragged;
// `hot` = the pointer is over it.
Rectangle {
    property bool hot: false
    property bool shown: EditMode.dragging

    readonly property color accent: Colors.color6
    visible: opacity > 0
    opacity: shown ? 1 : 0
    radius: 10
    color: Qt.rgba(accent.r, accent.g, accent.b, hot ? 0.22 : 0.10)
    border.width: hot ? 2 : 1
    border.color: Qt.rgba(accent.r, accent.g, accent.b, hot ? 0.95 : 0.55)
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on color { ColorAnimation { duration: 120 } }
}
