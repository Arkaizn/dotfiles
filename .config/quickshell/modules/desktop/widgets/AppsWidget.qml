import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// App shortcuts: one icon per app (its command, picked in the options); click starts it.
GridLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    columns: Math.max(1, Math.min(opts.columns ?? 4, apps.length))
    rowSpacing: 10
    columnSpacing: 10

    // the same command text the app picker stores
    function cmdOf(e) { return (e.command ?? []).map(c => /^[\w@%+=:,./-]+$/.test(c) ? c : "'" + c.replace(/'/g, "'\\''") + "'").join(" ") }
    readonly property var entries: Array.from(DesktopEntries.applications.values)
    readonly property var apps: (opts.apps ?? []).map(cmd => {
        const e = entries.find(x => cmdOf(x) === cmd)
        const base = cmd.split(" ")[0].replace(/.*\//, "")
        // the theme's icon, else one named like the program, else a glyph
        return { cmd: cmd, name: e?.name ?? base, icon: Quickshell.iconPath(e?.icon || base, true) }
    })
    readonly property real size: opts.iconSize ?? 44

    Text {
        visible: root.apps.length === 0
        text: "Add apps in the options"
        color: Colors.fade(0.5)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
    Repeater {
        model: root.apps
        Item {
            id: app
            required property var modelData
            implicitWidth: Math.max(root.size + 12, root.opts.labels !== false ? 72 : 0)
            implicitHeight: root.size + 12 + (root.opts.labels !== false ? 18 : 0)
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: mouse.containsMouse ? Colors.fade(0.1) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            Text {
                visible: app.modelData.icon === ""
                anchors.centerIn: icon
                text: "󰣆"
                color: Colors.fade(0.7)
                font.pixelSize: root.size * 0.8
                font.family: Properties.fontFamily
            }
            IconImage {
                id: icon
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
                implicitSize: root.size
                visible: app.modelData.icon !== ""
                source: app.modelData.icon
                scale: mouse.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
            }
            Text {
                visible: root.opts.labels !== false
                anchors { top: icon.bottom; topMargin: 3; horizontalCenter: parent.horizontalCenter }
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: app.modelData.name
                elide: Text.ElideRight
                color: Colors.ink
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                enabled: root.interactive
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["sh", "-c", app.modelData.cmd])
            }
        }
    }
}
