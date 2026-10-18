import QtQuick
import QtQuick.Layouts
import qs.services

// Output of one diagnostics job (Jobs state): the last lines, monospace,
// stderr in red, plus how it ended.
ColumnLayout {
    id: root
    property string jobId
    property int maxLines: 30
    readonly property var st: Jobs.state(jobId)
    // stderr is only shown in red when the command failed (nc reports success on stderr)
    readonly property bool failed: !st.running && st.code > 0
    visible: st.lines.length > 0 || st.running || st.missing !== undefined && st.missing !== ""
    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        implicitHeight: out.implicitHeight + 16
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.3)
        Text {
            id: out
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            textFormat: Text.StyledText
            text: root.st.missing ? "<font color='#f9e2af'>" + root.st.missing + " isn't installed: " + Jobs.installHint(root.st.missing) + "</font>"
                : root.st.lines.slice(-root.maxLines).map(l => (l.err && root.failed ? "<font color='#f38ba8'>" : "") + l.text.replace(/&/g, "&amp;").replace(/</g, "&lt;") + (l.err && root.failed ? "</font>" : "")).join("<br>")
                  + (root.st.running ? "<br><font color='#888888'>…</font>" : "")
            color: Qt.rgba(1, 1, 1, 0.8)
            font.pixelSize: 11
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
        }
    }
    Text {
        Layout.leftMargin: 16
        Layout.bottomMargin: 10
        visible: !root.st.running && root.st.code !== -1 && !root.st.missing
        text: root.st.cancelled ? "cancelled" : root.st.timedOut ? "stopped: took too long" : "exit " + root.st.code
        color: root.st.code === 0 ? Qt.rgba(1, 1, 1, 0.4) : "#f9e2af"
        font.pixelSize: 10
        font.family: Properties.fontFamily
    }
}
