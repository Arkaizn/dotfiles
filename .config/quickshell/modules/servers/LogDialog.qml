import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.components

// A run's or a server's log inside the app, opened at the first line that went wrong
// (the lines the script marks ✗ / ✘, a failed command, an error).
//   LogDialog { id: l }   l.start("svs-docker02", "/…/logs/20261110_002200-update.svs-docker02.log")
Modal {
    id: root

    cardWidth: 980
    property string title: ""
    property string path: ""
    property var rows: []
    property int first: -1                  // the first problem line
    property bool loading: false
    property string error: ""

    // ("not healthy yet" lines are the waiting, not the verdict)
    function bad(t) { return !/not healthy yet/.test(t) && /✗|✘|\bfailed\b|\bError\b|\berror:|unhealthy|did not come back|refused/.test(t) }
    function warn(t) { return /⚠|⊘|not healthy yet|Rolling back|aborted/.test(t) }
    function start(name, file) {
        title = name; path = file; rows = []; first = -1; error = ""; loading = true
        open()
        ServerStore.readLog(file, text => {
            if (root.path !== file) return
            loading = false
            if (text === null) { error = "The log isn't there any more (logs are kept " + "for a while, then removed)"; return }
            const list = text.split("\n")
            while (list.length && list[list.length - 1].trim() === "") list.pop()
            rows = list
            first = list.findIndex(l => root.bad(l))
            Qt.callLater(() => { if (root.first >= 0) view.positionViewAtIndex(Math.max(0, root.first - 3), ListView.Beginning); else view.positionViewAtEnd() })
        })
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Log  ·  " + root.title; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text {
                    Layout.fillWidth: true
                    text: root.loading ? "Reading…" : root.error !== "" ? root.error
                        : root.rows.length + " lines" + (root.first >= 0 ? "  ·  opened at the first problem (line " + (root.first + 1) + ")" : "  ·  no problem line found, opened at the end")
                    color: root.error !== "" ? Colors.red : Colors.textMuted
                    font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight
                }
            }
            IconButton {
                visible: root.first >= 0
                icon: "󰀦"; tooltip: "Go to the first problem"
                onClicked: view.positionViewAtIndex(Math.max(0, root.first - 3), ListView.Beginning)
            }
            IconButton { icon: "󰁅"; tooltip: "Go to the end"; onClicked: view.positionViewAtEnd() }
            IconButton { icon: "󰏌"; tooltip: "Open the file in your editor"; interactive: root.error === ""; onClicked: Qt.openUrlExternally("file://" + root.path) }
            IconButton { icon: "󰅖"; tooltip: "Close  (Esc)"; onClicked: root.close() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 520
            radius: Tokens.radius.md
            color: Colors.surfaceWell
            border.width: Tokens.border.thin
            border.color: Colors.lineSubtle
            clip: true
            Spinner { anchors.centerIn: parent; visible: root.loading; running: visible }
            ListView {
                id: view
                anchors.fill: parent
                anchors.margins: Tokens.space.s8
                clip: true
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SlimScrollBar {}
                SmoothWheel { flick: view; step: 120 }
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool isBad: root.bad(modelData)
                    width: view.width - 14
                    height: line.implicitHeight
                    radius: Tokens.radius.xs
                    color: index === root.first ? Colors.tint(Colors.red, 0.16) : "transparent"
                    Text {
                        id: line
                        width: parent.width
                        text: parent.modelData === "" ? " " : parent.modelData
                        color: parent.isBad ? Colors.red : root.warn(parent.modelData) ? Colors.orange : /✓|✔/.test(parent.modelData) ? Colors.green : Colors.textSecondary
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
