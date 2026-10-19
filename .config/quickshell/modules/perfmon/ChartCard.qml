import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// a history chart with clickable legend entries (hide / show a line)
PerfCard {
    id: cc
    property var seriesList: []
    property var hidden: ({})
    property alias chart: chart
    property int span: 60
    readonly property var available: seriesList.filter(s => s.show !== false)
    Layout.fillWidth: true
    actions: Repeater {
        model: cc.available
        Item {
            id: chip
            required property var modelData
            readonly property bool off: cc.hidden[modelData.label] === true
            implicitWidth: chipRow.implicitWidth + 16
            implicitHeight: 24
            Rectangle { anchors.fill: parent; radius: height / 2; color: chipMouse.containsMouse ? Colors.fade(0.08) : "transparent"; border.width: 1; border.color: Colors.fade(chip.off ? 0.06 : 0.12) }
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: chip.off ? Colors.fade(0.2) : chip.modelData.color }
                Text {
                    readonly property var vals: chip.modelData.values
                    readonly property real last: vals.length ? vals[vals.length - 1] : -1
                    text: chip.modelData.label + (last >= 0 && !chip.off ? "  " + chart.format(last) : "")
                    color: chip.off ? Colors.fade(0.35) : Colors.fade(0.8)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { const h = Object.assign({}, cc.hidden); h[chip.modelData.label] = !chip.off; cc.hidden = h }
            }
        }
    }
    Chart {
        id: chart
        Layout.fillWidth: true
        Layout.preferredHeight: 190
        span: cc.span
        interval: PerfMon.interval
        series: cc.available.filter(s => cc.hidden[s.label] !== true)
    }
}
