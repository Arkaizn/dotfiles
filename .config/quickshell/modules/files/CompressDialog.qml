import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmPath.js" as FmPath

// Compress: the archive's name, its format, a password (zip with AES / 7z with
// the names hidden too — given to 7z through its prompt, never its command line).
//   CompressDialog { onCreate: (name, format, password) => … }   start(defaultName, fs)
Modal {
    id: root

    signal create(string name, string format, string password)
    cardWidth: 480
    property string fs: ""
    property string format: "zip"
    readonly property string problem: FmPath.validName(name.text + "." + format, fs)

    function start(n, f) {
        fs = f ?? ""
        name.text = n
        pass.text = ""
        open()
        name.forceActiveFocus()
        name.selectAll()
    }
    function go() {
        if (problem !== "") return
        const p = format === "zip" || format === "7z" ? pass.text : ""
        pass.text = ""
        close()
        create(name.text, format, p)
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        Text { Layout.fillWidth: true; text: "Compress"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            SearchField { id: name; Layout.fillWidth: true; icon: ""; onAccepted: root.go() }
            Text { text: "." + root.format; color: Colors.fade(0.6); font.pixelSize: Tokens.font.body; font.family: Properties.fontFamily }
        }
        Segmented {
            options: ["zip", "tar.xz", "tar.gz", "7z"]
            value: root.format
            onEdited: v => root.format = v
        }
        SearchField {
            id: pass
            visible: root.format === "zip" || root.format === "7z"
            Layout.fillWidth: true
            password: true
            icon: "\u{F0306}"
            placeholderText: "Password (optional)"
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: name.text !== "" ? root.problem : ""
            color: Colors.danger; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { text: "Create"; variant: "primary"; interactive: root.problem === ""; onClicked: root.go() }
        }
    }
}
