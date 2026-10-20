import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.lib

// Network speed over all interfaces (SysStats, every 2 s while shown), graph of the last 2 minutes.
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 8
    implicitWidth: 240

    property bool using: false
    function use(on) { if (on === using) return; using = on; on ? SysStats.acquire(2000) : SysStats.release(2000) }
    onActiveChanged: use(active)
    Component.onCompleted: use(active)
    Component.onDestruction: use(false)

    property var down: []
    property var upl: []
    Connections {
        target: SysStats
        function onRxRateChanged() { root.down = root.down.concat([SysStats.rxRate]).slice(-60) }
        function onTxRateChanged() { root.upl = root.upl.concat([SysStats.txRate]).slice(-60) }
    }
    function rate(b) { return Format.bytes(b) + "/s" }

    RowLayout {
        Layout.fillWidth: true
        spacing: 16
        Text { text: "󰇚 " + root.rate(SysStats.rxRate); color: Colors.color6; font.pixelSize: 15; font.bold: true; font.family: Properties.fontFamily }
        Text { text: "󰕒 " + root.rate(SysStats.txRate); color: Colors.color4; font.pixelSize: 15; font.bold: true; font.family: Properties.fontFamily }
    }
    Item {
        visible: root.opts.graph !== false
        Layout.fillWidth: true
        implicitHeight: 54
        // one scale for both lines
        readonly property real peak: Math.max(1024, ...root.down, ...root.upl)
        Spark { anchors.fill: parent; values: root.down; max: parent.peak; color: Colors.color6 }
        Spark { anchors.fill: parent; values: root.upl; max: parent.peak; color: Colors.color4 }
    }
}
