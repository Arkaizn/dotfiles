import QtQuick

import qs.services
// The 16 colors of a pywal scheme as a strip of squares (two rows with `rows: 2`).
Grid {
    id: root
    property var colors: ({})              // { color0 … color15 }
    property int size: 14
    rows: 1
    spacing: 2
    Repeater {
        model: 16
        Rectangle {
            required property int index
            width: root.size
            height: root.size
            radius: 3
            color: root.colors?.["color" + index] ?? "transparent"
            border.width: 1
            border.color: Colors.fade(0.12)
        }
    }
}
