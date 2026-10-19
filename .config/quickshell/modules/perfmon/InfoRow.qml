import QtQuick
import QtQuick.Layouts
import qs.services

// "label ……… value" line of a performance card, with an optional bar (0–1)
// that turns yellow / red when nearly full.
ColumnLayout {
    id: root
    property string label
    property string value
    property string detail: ""          // dim text after the value
    property real bar: -1
    property color barColor: Colors.color6
    property bool warnColors: true
    Layout.fillWidth: true
    spacing: 4
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text { Layout.fillWidth: true; text: root.label; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideRight }
        Text { text: root.value; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
        Text { visible: root.detail !== ""; text: root.detail; color: Colors.fade(0.42); font.pixelSize: 11; font.family: Properties.fontFamily }
    }
    Rectangle {
        visible: root.bar >= 0
        Layout.fillWidth: true
        implicitHeight: 5
        radius: 2.5
        color: Colors.fade(0.07)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.bar))
            height: parent.height
            radius: 2.5
            color: root.warnColors && root.bar > 0.9 ? Colors.red : root.warnColors && root.bar > 0.75 ? Colors.yellow : root.barColor
        }
    }
}
