import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// How one server came out of a run: its status, the one sentence the script wrote about
// it (`summary`), and the ways to the place to look. Used by the activity panel (a run
// that just ended) and by the list of past updates.
//
//   ResultRow { name: "svs-docker02"; result: r; logPath: "…"; onLogRequested: … }
//   result: { status, summary, look: [{ kind, name }], problems, notes, reboot, packages, containers }
ColumnLayout {
    id: root

    property string name: ""
    property var result: ({})
    property string logPath: ""             // this server's log of that run ("" = none)
    property bool actions: true             // false: the sentence only (a narrow list)
    property bool quietWhenGood: false      // no buttons under a server that went fine (its log is one click away elsewhere)
    signal logRequested(string title, string path)
    signal checkRequested(string name)
    signal containerLogRequested(string name, string container)
    signal detailsRequested(string name)

    readonly property string st: result?.status ?? ""
    readonly property bool good: ["ok", "up-to-date", "healthy"].includes(st)
    readonly property color tone: st === "" ? Colors.textMuted : good ? Colors.green
        : ["rolled-back", "skipped", "pending", "aborted", "needs-look", "busy"].includes(st) ? Colors.orange : Colors.red
    readonly property var look: result?.look ?? []
    // older reports have no summary: the status and the first problem
    readonly property string sentence: (result?.summary ?? "") !== "" ? result.summary
        : st + ((result?.problems ?? []).length ? ": " + result.problems[0] : "")
          + (result?.reboot === "pending" || result?.reboot === "manual" ? " · reboot by hand" : "")

    spacing: Tokens.space.s4

    Text {
        Layout.fillWidth: true
        visible: root.st !== ""
        text: root.sentence
        color: root.good ? Colors.textSecondary : root.tone
        font.pixelSize: Tokens.font.caption
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }
    Flow {
        Layout.fillWidth: true
        visible: root.actions && root.st !== "" && (!root.good || (root.logPath !== "" && !root.quietWhenGood))
        spacing: Tokens.space.s4
        ActionButton {
            visible: root.logPath !== ""
            implicitHeight: Tokens.size.controlSmall; variant: "ghost"; icon: "󰦪"; text: "Log"
            tooltip: "What happened on " + root.name + ", opened at the first problem"
            onClicked: root.logRequested(root.name, root.logPath)
        }
        ActionButton {
            visible: !root.good && !["busy", "unreachable", "skipped"].includes(root.st)
            implicitHeight: Tokens.size.controlSmall; variant: "ghost"; icon: "󰓙"; text: "Check again"
            tooltip: "Run its health checks now: changes nothing"
            onClicked: root.checkRequested(root.name)
        }
        Repeater {
            model: root.look.filter(l => l.kind === "container").slice(0, 3)
            ActionButton {
                required property var modelData
                implicitHeight: Tokens.size.controlSmall; variant: "ghost"; icon: "󰡨"; text: modelData.name
                tooltip: "The output of the container " + modelData.name + ", in a terminal on " + root.name
                onClicked: root.containerLogRequested(root.name, modelData.name)
            }
        }
        ActionButton {
            visible: root.look.some(l => l.kind === "check" || l.kind === "snapshot")
            implicitHeight: Tokens.size.controlSmall; variant: "ghost"; icon: "󰋼"
            text: root.look.some(l => l.kind === "snapshot") ? "Proxmox" : "Checks"
            tooltip: root.look.some(l => l.kind === "snapshot") ? "Its details: where it runs and its snapshots" : "Its details: the failing checks (" + root.look.filter(l => l.kind === "check").map(l => l.name).join(", ") + ")"
            onClicked: root.detailsRequested(root.name)
        }
    }
}
