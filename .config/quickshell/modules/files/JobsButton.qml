import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "lib/FmFormat.js" as FmFormat

// The toolbar's operations button (shown while something runs, and a minute
// after): a bar of the overall progress under it; click → each operation with
// its progress, time left, pause / resume, stop.
//   JobsButton { ops }
IconButton {
    id: root

    property Item backdrop: null          // shown blurred behind its popover (the window's content)

    required property var ops
    readonly property var running: ops.jobs.filter(j => j.state === "running")
    readonly property real fraction: {
        let b = 0, t = 0, d = 0, n = 0
        for (const j of running) { b += j.bytes; t += j.totalBytes; d += j.done; n += j.total }
        return t > 0 ? b / t : n > 0 ? d / n : 0
    }

    visible: ops.jobs.length > 0
    icon: running.length ? "󰇚" : "󰄬"
    active: pop.opened
    tooltip: running.length ? running.length + (running.length === 1 ? " operation running" : " operations running") : "Recent operations"
    onClicked: pop.opened ? pop.close() : pop.open()

    // a new operation from this window: show where its progress is
    property int _seen: 0
    Connections {
        target: root.ops
        function onJobsChanged() {
            const n = root.ops.jobs.length
            if (n > root._seen && root.ops.jobs[n - 1]?.state === "running" && root.visible) pulse.restart()
            root._seen = n
        }
    }
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: root; property: "scale"; to: 1.15; duration: Anim.fast; easing.type: Anim.standard }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: Anim.normal; easing.type: Anim.pop }
    }

    Rectangle {
        visible: root.running.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.space.s4
        height: Tokens.space.s2
        radius: Tokens.radius.xs
        color: Colors.fade(0.12)
        Rectangle {
            width: parent.width * root.fraction
            height: parent.height
            radius: parent.radius
            color: Colors.accent
            Behavior on width { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
        }
    }

    function eta(j) {
        const secs = (Date.now() - j.started) / 1000
        if (j.totalBytes <= 0 || j.bytes <= 0 || secs < 2) return ""
        const left = (j.totalBytes - j.bytes) / (j.bytes / secs)
        return left < 60 ? Math.ceil(left) + " s left" : Math.ceil(left / 60) + " min left"
    }
    function detail(j) {
        if (j.state === "failed") return j.error
        if (j.state === "cancelled") return "Stopped"
        if (j.state === "done") return "Done"
        const parts = []
        if (j.totalBytes > 0) parts.push(Format.bytes(j.bytes) + " of " + Format.bytes(j.totalBytes))
        else if (j.total > 0) parts.push(j.done + " of " + j.total)
        if (j.paused) parts.push("paused")
        else { const e = eta(j); if (e) parts.push(e) }
        return parts.join("  ·  ")
    }

    Popup {
        id: pop
        scale: AppZoom.at(root)
        transformOrigin: Popup.TopRight
        x: root.width - width
        y: root.height + Tokens.space.s6
        width: Tokens.size.row * 9
        padding: Tokens.space.s10
        background: PopoverBackground { backdrop: root.backdrop }
        // a press on its own button doesn't close it: the click then closes it (toggle, no reopen)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.fast; easing.type: Anim.standard }
            NumberAnimation { property: "scale"; from: 0.96 * AppZoom.at(root); to: AppZoom.at(root); duration: Anim.fast; easing.type: Anim.standard }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Anim.instant } }

        // the times left move on
        Timer { interval: 1000; repeat: true; running: pop.opened && root.running.length > 0; onTriggered: list.tick++ }

        contentItem: ColumnLayout {
            id: list
            property int tick: 0
            spacing: Tokens.space.s10
            Text {
                text: "OPERATIONS"
                color: Colors.fade(0.4)
                font.pixelSize: Tokens.font.micro
                font.bold: true
                font.letterSpacing: 0.6
                font.family: Properties.fontFamily
            }
            Repeater {
                model: root.ops.jobs.slice().reverse()
                ColumnLayout {
                    id: job
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.space.s4
                    readonly property bool live: modelData.state === "running"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space.s6
                        Text {
                            Layout.fillWidth: true
                            text: job.modelData.label
                            color: Colors.fade(0.88)
                            font.pixelSize: Tokens.font.small
                            font.family: Properties.fontFamily
                            elide: Text.ElideMiddle
                            textFormat: Text.PlainText
                        }
                        IconButton {
                            visible: job.live
                            implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall; iconSize: Tokens.icon.sm
                            icon: job.modelData.paused ? "󰐊" : "󰏤"
                            tooltip: job.modelData.paused ? "Go on" : "Pause"
                            onClicked: root.ops.pause(job.modelData.id, !job.modelData.paused)
                        }
                        IconButton {
                            implicitWidth: Tokens.size.controlSmall; implicitHeight: Tokens.size.controlSmall; iconSize: Tokens.icon.sm
                            icon: "󰅖"
                            tooltip: job.live ? "Stop" : "Remove from the list"
                            onClicked: job.live ? root.ops.cancel(job.modelData.id) : root.ops.forget(job.modelData.id)
                        }
                    }
                    Rectangle {
                        visible: job.live
                        Layout.fillWidth: true
                        implicitHeight: Tokens.space.s4
                        radius: height / 2
                        color: Colors.fade(0.1)
                        Rectangle {
                            readonly property real f: job.modelData.totalBytes > 0 ? job.modelData.bytes / job.modelData.totalBytes
                                                     : job.modelData.total > 0 ? job.modelData.done / job.modelData.total : 0
                            width: parent.width * Math.min(1, f)
                            height: parent.height
                            radius: parent.radius
                            color: job.modelData.paused ? Colors.warning : Colors.accent
                            Behavior on width { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: { list.tick; return root.detail(job.modelData) + (job.live && job.modelData.current ? "  ·  " + FmFormat.shown(job.modelData.current) : "") }
                        color: job.modelData.state === "failed" ? Colors.danger : Colors.fade(0.5)
                        font.pixelSize: Tokens.font.caption
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
}
