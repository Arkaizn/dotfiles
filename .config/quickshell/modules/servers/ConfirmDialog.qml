import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// "Really?" for something that can't be undone.
//   ConfirmDialog { id: c }   c.ask("Delete svs-mc01?", "It's removed from servers.json…", "Delete", () => …)
Modal {
    id: root

    cardWidth: 420
    property string title: ""
    property string text: ""
    property string action: "Delete"
    property var run: null

    function ask(t, body, act, fn) { title = t; text = body; action = act; run = fn; open() }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14
        Text { Layout.fillWidth: true; text: root.title; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
        Text { Layout.fillWidth: true; text: root.text; color: Colors.textSecondary; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { icon: /^Delete/.test(root.action) ? "󰆴" : "󰜺"; text: root.action; variant: "danger"; onClicked: { const f = root.run; root.close(); if (f) f() } }
        }
    }
}
