import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.services.lib
import qs.components

// The past updates, inside the app (they are the script's reports/*.json): when, how it
// went, and for every server the sentence about it with the ways to the place to look.
//   HistoryDialog { id: h }   h.start("")              every update
//                             h.start("svs-docker02")   the updates of that server
Modal {
    id: root

    cardWidth: 900
    property string server: ""
    property var runs: []
    property bool loading: false
    property string open1: ""               // the report that is unfolded
    signal logRequested(string title, string path)
    signal checkRequested(string name)
    signal containerLogRequested(string name, string container)
    signal detailsRequested(string name)

    function start(name) {
        server = name ?? ""; runs = []; loading = true; open1 = ""
        open()
        ServerStore.history(server, 80, list => {
            runs = list
            loading = false
            // the newest one that didn't go well is unfolded; with one server, they all show their row anyway
            open1 = (list.find(r => r.result !== "OK") ?? list[0])?.file ?? ""
        })
    }
    function tone(r) { return r.result === "OK" ? Colors.green : r.result === "ATTENTION" ? Colors.orange : Colors.red }
    function word(r) { return r.result === "OK" ? "all good" : r.result === "ATTENTION" ? "needs a look" : "problems" }
    function counts(r) {
        const n = k => r.servers.filter(s => k.includes(s.status)).length
        return [[["ok"], "updated"], [["up-to-date"], "up to date"], [["needs-look"], "need a look"], [["rolled-back"], "rolled back"], [["failed"], "failed"],
                [["skipped"], "skipped"], [["unreachable"], "unreachable"], [["aborted"], "aborted"]]
               .map(x => n(x[0]) ? n(x[0]) + " " + x[1] : "").filter(x => x).join("  ·  ")
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: root.server === "" ? "Past updates" : "Past updates  ·  " + root.server; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text {
                    text: root.loading ? "Reading the reports…" : root.runs.length === 0 ? "" : root.runs.length + (root.runs.length === 1 ? " update" : " updates") + ", newest first"
                    color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                }
            }
            IconButton { icon: "󰅖"; tooltip: "Close  (Esc)"; onClicked: root.close() }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 540
            Spinner { anchors.centerIn: parent; visible: root.loading; running: visible }
            EmptyState {
                anchors.centerIn: parent
                visible: !root.loading && root.runs.length === 0
                icon: "󰋚"
                text: root.server === "" ? "No updates yet" : "No update of " + root.server + " yet"
            }
            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.runs
                spacing: Tokens.space.s8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SlimScrollBar {}
                SmoothWheel { flick: list; step: 120 }
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    readonly property bool unfolded: root.server !== "" || root.open1 === modelData.file
                    width: list.width - 14
                    height: body.implicitHeight + Tokens.space.s20
                    radius: Tokens.radius.card
                    color: Colors.card
                    border.width: Tokens.border.thin
                    border.color: head.hovered ? Colors.alpha(root.tone(modelData), 0.5) : Properties.cardBorder
                    Behavior on border.color { ColorAnimation { duration: Anim.fast } }
                    Behavior on height { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                    clip: true
                    ColumnLayout {
                        id: body
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: Tokens.space.s10
                        spacing: Tokens.space.s8
                        Pressable {
                            id: head
                            Layout.fillWidth: true
                            implicitHeight: headRow.implicitHeight
                            interactive: root.server === ""
                            dimDisabled: false
                            showFocusRing: root.server === ""
                            accessibleName: "Update of " + Format.ago(Date.parse(item.modelData.time)) + ": " + root.word(item.modelData)
                            onClicked: root.open1 = item.unfolded ? "" : item.modelData.file
                            RowLayout {
                                id: headRow
                                anchors.left: parent.left; anchors.right: parent.right
                                spacing: Tokens.space.s10
                                Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: root.tone(item.modelData) }
                                Text {
                                    text: new Date(item.modelData.time).toLocaleString(Qt.locale(), "ddd d MMM yyyy, HH:mm")
                                    color: Colors.ink; font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily
                                }
                                Text { text: Format.ago(Date.parse(item.modelData.time)); color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.word(item.modelData) + "  ·  " + root.counts(item.modelData)
                                    color: root.tone(item.modelData); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                                    elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                                }
                                Chevron { visible: root.server === ""; open: item.unfolded }
                            }
                        }
                        Repeater {
                            model: item.unfolded ? item.modelData.servers : []
                            RowLayout {
                                id: srv
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Tokens.space.s10
                                Text {
                                    visible: root.server === ""
                                    Layout.preferredWidth: 140
                                    Layout.alignment: Qt.AlignTop
                                    text: srv.modelData.server
                                    color: Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight
                                }
                                ResultRow {
                                    Layout.fillWidth: true
                                    name: srv.modelData.server
                                    result: srv.modelData
                                    logPath: ServerStore.serverLogOf(item.modelData.log, srv.modelData.server)
                                    onLogRequested: (t, p) => root.logRequested(t, p)
                                    onCheckRequested: n => root.checkRequested(n)
                                    onContainerLogRequested: (n, c) => root.containerLogRequested(n, c)
                                    onDetailsRequested: n => root.detailsRequested(n)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
