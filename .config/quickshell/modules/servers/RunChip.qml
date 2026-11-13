import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// One run in the activity panel's row of runs (several can go at the same time): what
// it is, whether it is still going and how it ended. A click shows it in the panel.
//
//   RunChip { run: r; current: true; onPicked: ServerRuns.show(r.id) }
Pressable {
    id: root

    property var run: null
    property bool current: false
    signal picked()

    readonly property bool going: run?.busy ?? false
    readonly property bool asking: going && (run?.asks ?? []).some(a => !a.answered)
    readonly property bool bad: !going && (!!run?.error || run?.result === "FAILED")
    readonly property bool look: !going && run?.result === "ATTENTION"
    readonly property color tone: asking ? Colors.orange : going ? Colors.accent : bad ? Colors.red : look ? Colors.orange : Colors.green

    implicitHeight: Tokens.size.controlSmall
    implicitWidth: row.implicitWidth + Tokens.space.s20
    accessibleName: run ? ServerRuns.describeRun(run) : ""
    tooltip: !run ? "" : asking ? "Waits for your answer" : going ? "Still going: show it" : bad ? "Ended with problems: show it" : look ? "Something needs a look: show it" : "Finished: show it"
    focusRadius: height / 2
    onClicked: root.picked()

    scale: pressed ? Properties.onPressedButtonScale : 1
    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.current ? Colors.tint(root.tone, 0.16) : root.hovered ? Colors.fillHover : Colors.fillSubtle
        border.width: root.current ? Tokens.border.control : Tokens.border.thin
        border.color: root.current ? Colors.alpha(root.tone, 0.6) : root.hovered ? Colors.lineHover : Colors.lineControl
        Behavior on color { ColorAnimation { duration: Anim.fast } }
        Behavior on border.color { ColorAnimation { duration: Anim.fast } }
    }
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.space.gap
        Item {
            implicitWidth: Tokens.icon.md; implicitHeight: Tokens.icon.md
            Spinner { anchors.centerIn: parent; visible: root.going && !root.asking; running: visible; size: Tokens.font.small }
            Text {
                anchors.centerIn: parent
                visible: !root.going || root.asking
                text: root.asking ? "󰋗" : root.bad || root.look ? "󰀦" : "󰄬"
                color: root.tone
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
            }
        }
        Text {
            text: root.run ? ServerRuns.describeRun(root.run) : ""
            color: root.current ? Colors.ink : Colors.textSecondary
            font.pixelSize: Tokens.font.small
            font.bold: root.current
            font.family: Properties.fontFamily
        }
    }
}
