import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

// Small pill with a value (address, MAC, …). Click (or Space / Enter)
// copies it to the clipboard; the pill flashes and says "copied". With
// `removable` it gets an × instead (list editors; Delete removes it too).
//
//   ValueChip { label: "GW"; text: "192.168.1.1" }
//   ValueChip { text: host; removable: true; onRemoved: drop(host) }
Pressable {
    id: root
    property string text: ""
    property string label: ""            // dim prefix, e.g. "GW"
    property bool copyable: true
    property bool removable: false
    property bool invalid: false
    property bool accent: false
    signal removed()

    property bool copied: false

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24
    interactive: (copyable || removable) && text !== ""
    dimDisabled: false
    showFocusRing: interactive
    accessibleName: (label !== "" ? label + " " : "") + text + (removable ? ", remove with Delete" : copyable ? ", copy" : "")
    focusRadius: height / 2
    cursorShape: removable ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: {
        if (removable || !copyable) return
        Quickshell.execDetached(["wl-copy", "--", root.text])
        root.copied = true
        copiedTimer.restart()
    }
    Keys.onDeletePressed: if (removable) removed()

    // pop in when created (list editors adding a value)
    scale: 0.85
    opacity: 0
    Component.onCompleted: { scale = 1; opacity = 1 }
    Behavior on scale { NumberAnimation { duration: Anim.medium; easing.type: Anim.pop } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.invalid ? Colors.alpha(Colors.danger, 0.16)
             : root.copied ? Colors.alpha(Colors.accent, 0.3)
             : root.accent ? Colors.alpha(Colors.accent, 0.14)
             : Colors.fade(root.hovered && root.copyable && !root.removable ? 0.12 : 0.07)
        border.width: Tokens.border.thin
        border.color: root.invalid ? Colors.alpha(Colors.danger, 0.5)
                    : root.accent || root.copied ? Colors.alpha(Colors.accent, 0.45)
                    : Colors.fade(0.1)
        Behavior on color { ColorAnimation { duration: Anim.normal } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: root.label !== ""
            text: root.label
            color: Colors.textMuted
            font.pixelSize: Tokens.font.micro
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            text: root.copied ? "copied" : root.text
            color: root.invalid ? Colors.danger : Colors.ink
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.removable
            text: "󰅖"
            color: Colors.fade(xMouse.containsMouse ? 0.95 : 0.5)
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            MouseArea {
                id: xMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removed()
            }
        }
    }
    Timer { id: copiedTimer; interval: 900; onTriggered: root.copied = false }
}
