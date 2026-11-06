import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// A question with a few answers: delete for good, run a program, trust a launcher.
//   ConfirmDialog { }   start({ icon, tone: "danger" | "warning" | "accent", title, text, detail,
//                               buttons: [{ label, variant, run }] })   (the last button is the right-most)
Modal {
    id: root

    cardWidth: 480
    // Enter never answers: a second Enter after opening a program must not run it
    enterAccepts: false
    property var opt: ({})
    readonly property color tone: opt.tone === "danger" ? Colors.danger : opt.tone === "warning" ? Colors.warning : Colors.accent

    function start(o) { opt = o; open() }
    function pick(b) { close(); if (b.run) b.run() }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(root.tone, 0.14)
                Text { anchors.centerIn: parent; text: root.opt.icon ?? ""; color: root.tone; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            Text {
                Layout.fillWidth: true
                text: root.opt.title ?? ""
                color: Colors.ink
                font.pixelSize: Tokens.font.subtitle
                font.bold: true
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
        Text {
            visible: text !== ""
            Layout.fillWidth: true
            text: root.opt.text ?? ""
            color: Colors.fade(0.85)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        // e.g. the command a launcher runs: shown as it is, in a well
        Rectangle {
            visible: (root.opt.detail ?? "") !== ""
            Layout.fillWidth: true
            implicitHeight: detail.implicitHeight + 2 * Tokens.space.s10
            radius: Tokens.radius.lg
            color: Colors.surfaceWell
            Text {
                id: detail
                anchors.fill: parent
                anchors.margins: Tokens.space.s10
                text: root.opt.detail ?? ""
                color: Colors.fade(0.75)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 6
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            layoutDirection: Qt.RightToLeft
            Repeater {
                model: (root.opt.buttons ?? []).slice().reverse()
                ActionButton {
                    required property var modelData
                    text: modelData.label
                    variant: modelData.variant ?? "default"
                    onClicked: root.pick(modelData)
                }
            }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
        }
    }
}
