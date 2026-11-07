import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat

// What a running operation asks (FmOps.question): a name that's taken — replace,
// skip, keep both (with a name), merge two folders —, an error (retry / skip),
// or a drive without a trash (delete for good / skip). "Do this for the rest"
// answers the same questions of that operation. Esc / Cancel stops the operation.
//   AskDialog { ops }   shows itself while ops.question is set (in the window used last)
Modal {
    id: root

    required property var ops
    property bool mine: true                   // this window shows the questions
    // conflicts and errors here; passwords and other questions: PasswordDialog
    readonly property var q: mine && ops.question && ["conflict", "error", "notrash"].includes(ops.question.kind) ? ops.question : null
    cardWidth: 520
    keepOpen: true                             // a click outside doesn't decide anything

    onQChanged: {
        if (q) {
            allBox.checked = false
            nameField.text = q.suggest ?? ""
            open()
        } else {
            close()
        }
    }
    // Esc / a click outside: the shake (keepOpen); "Stop" ends the operation
    function stop() { ops.answer("cancel") }
    // Enter: nothing gets overwritten or lost by it (the Modal would press the primary button)
    enterAccepts: false

    readonly property bool conflict: q?.kind === "conflict"
    function side(it) {
        if (!it) return ""
        const bits = [it.dir ? "Folder" : Format.bytes(it.size ?? 0)]
        if (it.mtime) bits.push("modified " + FmFormat.when(it.mtime, Date.now()))
        return bits.join("  ·  ")
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(root.conflict ? Colors.warning : Colors.danger, 0.14)
                Text { anchors.centerIn: parent; text: root.conflict ? FmIcons.g.file : FmIcons.g.alert
                       color: root.conflict ? Colors.warning : Colors.danger; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text {
                    Layout.fillWidth: true
                    text: !root.q ? "" : root.conflict ? (root.q.folders ? "A folder “" : "“") + FmFormat.shown(root.q.dst?.name ?? "") + "” is already there"
                        : root.q.kind === "notrash" ? "This can't go to the trash" : "Something went wrong"
                    color: Colors.ink
                    font.pixelSize: Tokens.font.subtitle
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    text: root.q?.label ?? ""
                    color: Colors.fade(0.5)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        // a conflict: the two side by side
        GridLayout {
            visible: root.conflict
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Tokens.space.s12
            rowSpacing: Tokens.space.s4
            Text { text: "Already there"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
            Text { Layout.fillWidth: true; text: root.side(root.q?.dst); color: Colors.fade(0.85); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight }
            Text { text: root.q?.restore ? "From the trash" : "New one"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
            Text { Layout.fillWidth: true; text: root.side(root.q?.src); color: Colors.fade(0.85); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight }
        }

        // an error: what and where
        Text {
            visible: !root.conflict
            Layout.fillWidth: true
            text: !root.q || root.conflict ? "" : "“" + FmFormat.shown((root.q.path ?? "").split("/").pop()) + "”: " + (root.q.error ?? "")
                  + (root.q.kind === "notrash" ? "\nDelete it for good instead? That can't be undone." : "")
            color: Colors.fade(0.85)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        // keep both: under which name
        RowLayout {
            visible: root.conflict
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Text { text: "Keep both as"; color: Colors.fade(0.6); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
            SearchField {
                id: nameField
                Layout.fillWidth: true
                icon: ""
                onAccepted: if (text.trim() !== "") root.ops.answer("rename", false, text)
            }
        }

        Checkbox {
            id: allBox
            Layout.fillWidth: true
            label: "Do this for the rest too"
            onClicked: checked = !checked
            visible: !(root.q?.restore)
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            layoutDirection: Qt.RightToLeft
            // the safe choice is the primary one: nothing gets overwritten / lost by Enter
            ActionButton {
                visible: root.conflict
                text: "Keep both"
                variant: "primary"
                interactive: nameField.text.trim() !== ""
                onClicked: root.ops.answer("rename", false, nameField.text)
            }
            ActionButton {
                visible: root.conflict && root.q?.folders === true
                text: "Merge"
                onClicked: root.ops.answer("merge", allBox.checked)
            }
            ActionButton {
                visible: root.conflict && !root.q?.folders && !root.q?.restore
                text: "Replace"
                variant: "danger"
                onClicked: root.ops.answer("replace", allBox.checked)
            }
            ActionButton {
                visible: root.q?.kind === "error"
                text: "Try again"
                variant: "primary"
                onClicked: root.ops.answer("retry", false)
            }
            ActionButton {
                visible: root.q?.kind === "notrash"
                text: "Delete for good"
                variant: "danger"
                onClicked: root.ops.answer("delete", allBox.checked)
            }
            ActionButton { text: "Skip"; onClicked: root.ops.answer("skip", allBox.checked) }
            ActionButton { text: "Stop"; variant: "ghost"; onClicked: root.stop() }
        }
    }
}
