import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.lib

// Used / free space of the chosen folders' drives (df, every minute while shown).
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 10
    implicitWidth: 250

    property var disks: []        // [{ path, size, used, avail }]
    function read() {
        const paths = (opts.paths ?? ["/"]).filter(p => p.startsWith("/"))
        if (paths.length === 0) { disks = []; return }
        Jobs.run(["df", "-B1", "--output=target,size,used,avail", "--"].concat(paths), (code, out) => {
            const seen = []
            root.disks = out.split("\n").slice(1).map(l => l.trim().split(/\s+/)).filter(f => f.length >= 4)
                .map(f => ({ path: f.slice(0, f.length - 3).join(" "), size: Number(f[f.length - 3]), used: Number(f[f.length - 2]), avail: Number(f[f.length - 1]) }))
                .filter(d => { if (seen.includes(d.path)) return false; seen.push(d.path); return true })
        })
    }
    onOptsChanged: if (active) read()
    Timer { running: root.active; interval: 60000; repeat: true; triggeredOnStart: true; onTriggered: root.read() }

    Text {
        visible: root.disks.length === 0
        text: "No drives"
        color: Colors.fade(0.5)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
    Repeater {
        model: root.disks
        ColumnLayout {
            id: d
            required property var modelData
            readonly property real part: modelData.size > 0 ? modelData.used / modelData.size : 0
            readonly property color tint: part > 0.9 ? Colors.red : part > 0.75 ? Colors.yellow : Colors.color6
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text { text: "󰋊"; color: d.tint; font.pixelSize: 14; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: d.modelData.path; color: Colors.ink; font.pixelSize: 12; font.bold: true; elide: Text.ElideMiddle; font.family: Properties.fontFamily }
                Text { text: Format.bytes(d.modelData.avail) + " free"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6; radius: 3
                color: Colors.fade(0.12)
                Rectangle { width: parent.width * d.part; height: parent.height; radius: 3; color: d.tint }
            }
        }
    }
}
