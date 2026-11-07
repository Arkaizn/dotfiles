import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmPath.js" as FmPath

// A name for something: rename, new folder, new document. Checked while typing
// (FmPath.validName, the drive's rules), a hint for hidden names; Enter takes it.
// The backend checks again and may still refuse ("already exists"): that shows here.
//   NameDialog { }   start({ title, icon, name, action: "Rename", fs, stem: true,
//                            taken: name => bool, run: (name, done) => … })   done(error) closes on ""
Modal {
    id: root

    cardWidth: 440
    property var opt: ({})
    property string error: ""
    property bool busy: false
    readonly property string problem: FmPath.validName(field.text, opt.fs ?? "")
                                    || (field.text !== (opt.name ?? "") && opt.taken && opt.taken(field.text) ? "“" + field.text + "” already exists here" : "")

    function start(o) {
        opt = o
        error = ""
        busy = false
        field.text = o.name ?? ""
        open()
        field.forceActiveFocus()
        // like Nautilus: the name without its extension is selected
        const n = field.text, dot = n.lastIndexOf(".")
        if (o.stem && dot > 0) field.select(0, n.toLowerCase().endsWith(".tar" + n.slice(dot).toLowerCase()) ? dot - 4 : dot)
        else field.selectAll()
    }
    function apply() {
        if (problem !== "" || busy) return
        if (field.text === (opt.name ?? "") && opt.stem) { close(); return }
        busy = true
        error = ""
        opt.run(field.text, err => {
            root.busy = false
            if (err) root.error = err
            else root.close()
        })
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s16

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: root.opt.icon ?? ""; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            Text {
                Layout.fillWidth: true
                text: root.opt.title ?? ""
                color: Colors.ink
                font.pixelSize: Tokens.font.subtitle
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
        }

        SearchField {
            id: field
            Layout.fillWidth: true
            icon: ""
            error: root.error !== ""
            onAccepted: root.apply()
            onTextChanged: root.error = ""
        }

        Text {
            Layout.fillWidth: true
            readonly property string warn: FmPath.nameWarning(field.text)
            visible: text !== ""
            text: root.error || (field.text !== "" ? root.problem : "") || warn
            color: root.error || root.problem ? Colors.danger : Colors.warning
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { text: root.opt.action ?? "OK"; variant: "primary"; busy: root.busy; interactive: root.problem === ""; onClicked: root.apply() }
        }
    }
}
