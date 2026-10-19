import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

ColumnLayout {
    id: og
    property string label
    property color accent
    property alias value: g.value
    property alias min: g.min
    property alias max: g.max
    property alias warn: g.warn
    property alias crit: g.crit
    property alias text: g.text
    property alias unit: g.unit
    property alias sub: g.sub
    property string caption
    Layout.fillWidth: true
    Layout.maximumWidth: Number.POSITIVE_INFINITY   // a layout is otherwise capped at its children
    Layout.alignment: Qt.AlignTop
    spacing: 8
    CapsLabel { Layout.alignment: Qt.AlignHCenter; text: og.label.toUpperCase(); dot: og.accent }
    Gauge { id: g; Layout.alignment: Qt.AlignHCenter; color: og.accent }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: og.caption
        color: Colors.fade(0.5)
        font.pixelSize: 11
        font.family: Properties.fontFamily
    }
}
