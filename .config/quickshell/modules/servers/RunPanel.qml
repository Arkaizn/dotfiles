import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// The bottom panel of the Servers app: what a scan / check / update is doing
// right now (or did last): progress, each server's step and result, and the
// log as it comes in (auto-scrolls until you scroll up).
//   RunPanel { open: … ; onCloseRequested: … ; onOpenRequested: … }
// Hidden, it stays as a slim bar at the bottom (headline, progress, ↑) while
// there is a run to show; a click on it opens it again.
Item {
    id: root

    property bool open: false
    signal closeRequested()
    signal openRequested()
    signal abortRequested()                  // the window confirms an update's abort
    signal retryRequested(var names)
    signal logRequested(string title, string path)
    signal containerLogRequested(string name, string container)
    signal detailsRequested(string name)
    signal historyRequested()         // the update confirmation again, for the ones that didn't go through
    readonly property var run: ServerRuns.run
    readonly property bool busy: ServerRuns.busy
    readonly property var asks: ServerRuns.asks
    readonly property var queue: ServerRuns.queue

    // its height when open: dragged on its top edge (remembered: ServerStore.prefs.panelHeight);
    // questions need room: at least 360 then
    property real maxHeight: 700
    property real dragHeight: -1
    readonly property real openHeight: Math.max(asks.length ? 360 : 180,
                                                Math.min(maxHeight, dragHeight >= 0 ? dragHeight : (Number(ServerStore.prefs.panelHeight) || 280)))
    // gone when there's nothing to show, or the last run was fine and it took itself away
    readonly property bool gone: !run || (ServerRuns.dismissed && !busy && queue.length === 0)
    implicitHeight: gone ? 0 : open ? openHeight : 52
    clip: true
    visible: implicitHeight > 0.5
    Behavior on implicitHeight { enabled: root.dragHeight < 0; NumberAnimation { duration: open ? Anim.slow : Anim.normal; easing.type: open ? Anim.emphasized : Anim.exit } }

    // a tick for the countdown of a question
    property real tick: Date.now()
    Timer { interval: 1000; repeat: true; running: root.asks.length > 0 && root.open; onTriggered: root.tick = Date.now() }

    readonly property var modeName: ({ scan: "Scan", check: "Health checks", update: "Update", command: "Command", snapshots: "Deleting snapshots" })
    readonly property string headline: {
        if (!run) return ""
        const n = run.servers.length
        const what = run.mode === "command" ? "“" + (run.opts?.title || "Command") + "” on " + n + (n === 1 ? " server" : " servers")
                   : run.mode === "snapshots" ? "Deleting " + (run.opts?.ids ?? []).length + " snapshots"
                   : run.mode === "update" ? (run.opts?.only === "security" ? "Security updates on " : "Updating ") + n + (n === 1 ? " server" : " servers")
                   : (modeName[run.mode] ?? run.mode) + " of " + n + (n === 1 ? " server" : " servers")
        const more = ServerRuns.busyRuns.filter(r => r.id !== run.id).length
        // over: what it was, then how it went
        const was = what.replace(/^Updating /, "Update of ").replace(/^Security updates on /, "Security updates of ")
        if (busy) return (asks.length ? "Needs your decision  ·  " : run.aborting ? "Aborting  ·  " : "") + what + (more ? "  ·  +" + more + " more running" : "")
                         + (queue.length ? "  ·  then " + queue.length + " more" : "")
        return was + "  ·  " + (run.error ? "stopped: " + run.error : run.mode === "update" || run.mode === "check" ? (ServerRuns.tally(run) || "nothing to do") : run.result === "OK" ? "all good" : run.result === "FAILED" ? "problems found" : "done")
    }
    readonly property color tone: !run ? Colors.accent : busy && asks.length ? Colors.orange : busy ? Colors.accent : run.error || run.result === "FAILED" ? Colors.red : run.result === "ATTENTION" ? Colors.orange : Colors.green

    // a tick while running, for the elapsed time
    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: root.busy && root.open; onTriggered: root.now = Date.now() }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.topMargin: Tokens.space.s4
        radius: Tokens.radius.lg
        border.width: 1
        border.color: Colors.alpha(root.tone, 0.35)
        Behavior on border.color { ColorAnimation { duration: Anim.medium } }
        color: !root.open && barHover.hovered ? Colors.fade(0.07) : Colors.card
        Behavior on color { ColorAnimation { duration: Anim.fast } }
        // the slim bar: a click anywhere on it opens the panel
        HoverHandler { id: barHover; enabled: !root.open; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !root.open; onTapped: root.openRequested() }

        // the top edge: drag to make it taller / smaller, double-click resets
        MouseArea {
            id: grip
            visible: root.open
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: Tokens.space.s8
            z: 2
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeVerCursor
            property real startY: 0
            property real startH: 0
            onPressed: m => { startY = mapToItem(null, 0, m.y).y; startH = root.openHeight; root.dragHeight = startH }
            onPositionChanged: m => { if (pressed) root.dragHeight = startH - (mapToItem(null, 0, m.y).y - startY) }
            onReleased: { ServerStore.setPref("panelHeight", Math.round(root.openHeight)); root.dragHeight = -1 }
            onDoubleClicked: { root.dragHeight = -1; ServerStore.setPref("panelHeight", 280) }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 2; width: 44; height: 3; radius: 1.5
                color: Colors.fade(grip.pressed ? 0.7 : grip.containsMouse ? 0.45 : 0.14)
                Behavior on color { ColorAnimation { duration: Anim.fast } }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.space.s12
            spacing: Tokens.space.s8

            // several runs: one chip each, the shown one marked; a click shows another
            Flow {
                Layout.fillWidth: true
                visible: root.open && ServerRuns.runs.length > 1
                spacing: Tokens.space.s6
                Repeater {
                    model: ServerRuns.runs
                    delegate: RunChip {
                        required property var modelData
                        run: modelData
                        current: root.run !== null && modelData.id === root.run.id
                        onPicked: ServerRuns.show(modelData.id)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s8
                Spinner { visible: root.busy; running: root.busy; size: Tokens.font.subtitle }
                Text {
                    visible: !root.busy
                    text: root.run?.error || root.run?.result === "FAILED" ? "󰀦" : "󰄬"
                    color: root.tone
                    font.pixelSize: Tokens.font.subtitle
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.headline
                    color: Colors.ink
                    font.pixelSize: Tokens.font.body
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    text: root.run ? (root.busy ? Format.hm(root.run.started) + "  ·  " + Math.floor((root.now - root.run.started) / 60000) + ":"
                                                  + String(Math.floor((root.now - root.run.started) / 1000) % 60).padStart(2, "0")
                                                : "started " + Format.hm(root.run.started)) : ""
                    color: Colors.textMuted
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
                ActionButton {
                    visible: root.busy && root.run?.mode === "update"
                    icon: "󰓛"; text: "Finish these, start nothing new"
                    tooltip: "The servers being updated right now finish normally; the waiting ones aren't started"
                    interactive: !(root.run?.aborting ?? false)
                    onClicked: ServerRuns.stop()
                }
                ActionButton {
                    visible: root.busy
                    icon: "󰜺"; text: root.run?.aborting ? "Kill now…" : "Abort"
                    variant: "danger"
                    tooltip: root.run?.aborting ? "It's stopping at the next safe point; this cuts it off right now (asks first)"
                           : root.run?.mode === "update" ? "Stop every server at its next safe point (asks first)" : "Stop it now"
                    onClicked: root.abortRequested()
                }
                IconButton {
                    icon: "󰋚"; tooltip: "Past updates"
                    onClicked: root.historyRequested()
                }
                ActionButton {
                    visible: ServerRuns.retryable.length > 0
                    icon: "󰑓"; text: "Retry " + ServerRuns.retryable.length
                    tooltip: "The update confirmation again, for: " + ServerRuns.retryable.join(", ")
                    onClicked: root.retryRequested(ServerRuns.retryable)
                }
                ActionButton {
                    visible: !root.busy && (root.run?.report ?? "") !== ""
                    icon: "󰈙"; text: "Report"
                    onClicked: Qt.openUrlExternally("file://" + root.run.report.replace(/\.json$/, ".md"))
                }
                IconButton {
                    visible: (root.run?.log ?? "") !== ""
                    implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm
                    icon: "󰦪"; tooltip: "The whole log (text editor)"
                    onClicked: Qt.openUrlExternally("file://" + root.run.log)
                }
                IconButton {
                    implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm
                    icon: root.open ? "󰅀" : "󰅃"
                    tooltip: root.open ? "Make it small (it keeps running)  (Ctrl+L)" : "Show the details  (Ctrl+L)"
                    onClicked: root.open ? root.closeRequested() : root.openRequested()
                }
            }

            // progress: eases to each new value
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Colors.fade(0.08)
                Rectangle {
                    width: parent.width * (root.busy ? Math.max(0.03, ServerRuns.progress) : 1)
                    height: parent.height
                    radius: 2
                    color: root.tone
                    Behavior on width { NumberAnimation { duration: Anim.slow; easing.type: Anim.standard } }
                    Behavior on color { ColorAnimation { duration: Anim.medium } }
                }
            }

            // what comes after this run (start something while it runs and it lands here)
            RowLayout {
                Layout.fillWidth: true
                visible: root.open && root.queue.length > 0
                spacing: Tokens.space.s6
                Text { text: ServerRuns.paused ? "Waiting (after the abort)" : "Next"; color: ServerRuns.paused ? Colors.orange : Colors.textSecondary
                       font.pixelSize: Tokens.font.caption; font.bold: true; font.family: Properties.fontFamily }
                ActionButton { visible: ServerRuns.paused; icon: "󰐊"; text: "Continue"; onClicked: ServerRuns.resume() }
                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Tokens.space.s4
                    Repeater {
                        model: root.queue
                        Rectangle {
                            id: qchip
                            required property var modelData
                            required property int index
                            implicitWidth: qrow.implicitWidth + 14
                            implicitHeight: 22
                            radius: 11
                            color: Colors.fade(0.07)
                            border.width: 1
                            border.color: Colors.fade(0.12)
                            Row {
                                id: qrow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (qchip.index + 1) + ". " + ServerRuns.describe(qchip.modelData) + (qchip.modelData.auto ? "  (auto)" : "")
                                    color: Colors.textSecondary; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                                }
                                Pressable {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 16; implicitHeight: 16
                                    tooltip: "Take it out of the queue"
                                    onClicked: ServerRuns.removeQueued(qchip.modelData.id)
                                    Text { anchors.centerIn: parent; text: "󰅖"; color: parent.hovered ? Colors.red : Colors.textMuted
                                           font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                                }
                            }
                        }
                    }
                }
            }

            // the script asks: what happened, why one would (not) roll back, the choices
            Repeater {
                model: root.open ? root.asks : []
                Rectangle {
                    id: askCard
                    required property var modelData
                    readonly property real remain: Math.max(0, modelData.timeout - (root.tick - modelData.time) / 1000)
                    Layout.fillWidth: true
                    implicitHeight: askCol.implicitHeight + 2 * Tokens.space.s10
                    radius: Tokens.radius.md
                    color: Colors.alpha(Colors.orange, 0.10)
                    border.width: 1
                    border.color: Colors.alpha(Colors.orange, 0.45)
                    ColumnLayout {
                        id: askCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space.s10
                        spacing: Tokens.space.s6
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "󰋗"; color: Colors.orange; font.pixelSize: Tokens.font.subtitle; font.family: Properties.fontFamily }
                            Text {
                                Layout.fillWidth: true
                                text: askCard.modelData.question
                                color: Colors.ink; font.pixelSize: Tokens.font.small; font.bold: true; font.family: Properties.fontFamily; wrapMode: Text.Wrap
                            }
                            Text {
                                text: "decides by itself in " + Math.floor(askCard.remain / 60) + ":" + String(Math.floor(askCard.remain) % 60).padStart(2, "0")
                                color: Colors.textMuted; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: askCard.modelData.detail
                            color: Colors.textSecondary; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                            wrapMode: Text.Wrap; textFormat: Text.PlainText
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: Tokens.space.s6
                            Repeater {
                                model: askCard.modelData.options
                                ActionButton {
                                    required property string modelData
                                    text: modelData
                                    variant: /^(Keep|No|Stop)/.test(modelData) ? "default" : "primary"
                                    onClicked: ServerRuns.answer(askCard.modelData.id, modelData)
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.space.s12
                visible: root.open
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }

                // each server: its step / result
                ListView {
                    id: servers
                    // wider once an update is over: the sentences need the room more than the log does
                    Layout.preferredWidth: !root.busy && root.run?.mode === "update" ? Math.min(560, root.width * 0.5) : 330
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
                    Layout.fillHeight: true
                    clip: true
                    model: root.run?.servers ?? []
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: SlimScrollBar {}
                    delegate: Item {
                        id: srow
                        required property string modelData
                        readonly property var p: root.run?.per[modelData] ?? {}
                        readonly property string st: p.status ?? ""
                        readonly property color c: st === "" ? Colors.textMuted
                            : ["ok", "up-to-date", "healthy"].includes(st) ? Colors.green
                            : ["rolled-back", "skipped", "pending", "aborted", "needs-look", "busy"].includes(st) ? Colors.orange : Colors.red
                        // an update that is over: the sentence about it and the ways to the place to look
                        readonly property bool told: st !== "" && root.run?.mode === "update" && !["ok", "up-to-date"].includes(st) || (st !== "" && (p.summary ?? "") !== "" && root.run?.mode === "update")
                        width: servers.width - 14   // room for the scroll bar (12 px), so it never sits on a button
                        height: told ? 24 + more.implicitHeight + Tokens.space.s6 : 24
                        ResultRow {
                            id: more
                            visible: srow.told
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: 22; anchors.topMargin: 24
                            name: srow.modelData
                            result: srow.p
                            logPath: srow.p.log ?? ""
                            quietWhenGood: true
                            onLogRequested: (t, f) => root.logRequested(t, f)
                            onCheckRequested: n => ServerRuns.start("check", [n], {}, "alongside")
                            onContainerLogRequested: (n, c) => root.containerLogRequested(n, c)
                            onDetailsRequested: n => root.detailsRequested(n)
                        }
                        RowLayout {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: 24
                            spacing: Tokens.space.s6
                            Item {
                                implicitWidth: 16; implicitHeight: 16
                                Spinner { anchors.centerIn: parent; visible: srow.st === "" && (srow.p.phase ?? "") !== "" && root.busy; running: visible; size: Tokens.font.small }
                                Text {
                                    id: mark
                                    anchors.centerIn: parent
                                    visible: srow.st !== "" || (srow.p.phase ?? "") === "" || !root.busy
                                    text: srow.st === "" ? "·" : ["ok", "up-to-date", "healthy"].includes(srow.st) ? "󰄬" : srow.st === "aborted" ? "󰜺" : srow.st === "needs-look" ? "󰀦" : srow.st === "busy" ? "󰔟" : ["rolled-back", "skipped", "pending"].includes(srow.st) ? "󰜉" : "󰅖"
                                    color: srow.c
                                    font.pixelSize: Tokens.font.small
                                    font.family: Properties.fontFamily
                                    // pops in with the result
                                    scale: 1
                                    onTextChanged: if (srow.st !== "") pop.restart()
                                    SequentialAnimation {
                                        id: pop
                                        NumberAnimation { target: mark; property: "scale"; from: 0.4; to: 1.25; duration: Anim.fast; easing.type: Anim.standard }
                                        NumberAnimation { target: mark; property: "scale"; to: 1; duration: Anim.normal; easing.type: Anim.pop }
                                    }
                                }
                            }
                            Text {
                                Layout.preferredWidth: 120
                                text: srow.modelData
                                color: Colors.ink
                                font.pixelSize: Tokens.font.small
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: srow.st !== "" ? (srow.told ? srow.st.replace("needs-look", "needs a look").replace("rolled-back", "rolled back")
                                                                    : srow.st + ((srow.p.problems ?? []).length ? ": " + srow.p.problems[0] : "")
                                                                      + (srow.p.reboot === "pending" || srow.p.reboot === "manual" ? " · reboot by hand" : ""))
                                    : (srow.p.aborting ? "aborting · " : "") + ((srow.p.phase ?? "") || (root.busy ? (root.run.mode === "update" ? "waiting" : "running") : ""))
                                color: srow.st === "" ? Colors.textMuted : srow.c
                                font.pixelSize: Tokens.font.caption
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                            IconButton {
                                // only this server: a stuck verification, a scan that hangs
                                visible: root.busy && srow.st === "" && !(srow.p.aborting ?? false) && (root.run.mode !== "update" || (srow.p.phase ?? "") !== "")
                                         && root.run.mode !== "check" && root.run.mode !== "snapshots"
                                implicitWidth: 22; implicitHeight: 22; iconSize: Tokens.icon.xs
                                icon: "󰜺"
                                tooltip: root.run?.mode === "update" ? "Abort " + srow.modelData + ": it stops at its next safe point (a wait ends right away; a running install finishes first)"
                                                                     : "Abort " + srow.modelData
                                onClicked: ServerRuns.abortServer(srow.modelData)
                            }
                            IconButton {
                                visible: (srow.p.log ?? "") !== "" && (!srow.told || ["ok", "up-to-date"].includes(srow.st))
                                implicitWidth: 22; implicitHeight: 22; iconSize: Tokens.icon.xs
                                icon: "󰦪"; tooltip: "This server's log"
                                onClicked: root.logRequested(srow.modelData, srow.p.log)
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Colors.fade(0.08) }

                // the log, newest at the bottom; follows unless you scrolled up
                ListView {
                    id: lines
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.run?.lines ?? []
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: SlimScrollBar {}
                    SmoothWheel { flick: lines; step: 80 }
                    property bool follow: true
                    onMovementEnded: follow = atYEnd
                    onCountChanged: if (follow) Qt.callLater(() => lines.positionViewAtEnd())
                    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.normal } }
                    delegate: Text {
                        required property var modelData
                        width: lines.width - 14
                        text: (modelData.server ? "[" + modelData.server + "] " : "") + modelData.text
                        color: modelData.level === "error" ? Colors.red : modelData.level === "warn" ? Colors.orange
                             : modelData.level === "ok" ? Colors.green : modelData.level === "title" ? Colors.ink : Colors.textSecondary
                        font.pixelSize: Tokens.font.caption
                        font.bold: modelData.level === "title"
                        font.family: Properties.fontFamily
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
