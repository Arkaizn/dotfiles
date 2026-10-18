import QtQuick
import QtQuick.Layouts
import qs.services

// "label ……… value" line of a performance card, with an optional bar (0–1).
ColumnLayout {
    id: root
    property string label
    property string value
    property real bar: -1
    property color barColor: Colors.color6
    Layout.fillWidth: true
    spacing: 3
    RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: root.label; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideRight }
        Text { text: root.value; color: "white"; font.pixelSize: 12; font.family: Properties.fontFamily }
    }
    Rectangle {
        visible: root.bar >= 0
        Layout.fillWidth: true
        implicitHeight: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.08)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.bar))
            height: parent.height
            radius: 2
            color: root.bar > 0.9 ? "#f38ba8" : root.bar > 0.75 ? "#f9e2af" : root.barColor
        }
    }
}
