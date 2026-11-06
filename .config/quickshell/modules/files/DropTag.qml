import QtQuick
import qs.services
import "lib/FmIcons.js" as FmIcons

// The tag under a dragged card while it's over a folder: where it goes and how
// (into = move on the same drive / copy across, Ctrl: copy, Ctrl+Shift: link).
//   DropTag { name; action }   (action: Qt.MoveAction | Qt.CopyAction | Qt.LinkAction)
Rectangle {
    id: root

    property string name: ""
    property int action: Qt.MoveAction

    width: row.implicitWidth + 2 * Tokens.space.s10
    height: Tokens.font.small + 2 * Tokens.space.s6
    radius: height / 2
    color: Colors.accent

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: Tokens.space.s10
        spacing: Tokens.space.s6
        Text {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            text: root.action === Qt.LinkAction ? FmIcons.g.link : root.action === Qt.CopyAction ? FmIcons.g.copy : FmIcons.g.folderOpen
            color: Colors.onAccent
            font.pixelSize: Tokens.font.body
            font.family: Properties.fontFamily
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Tokens.size.row * 8)
            text: (root.action === Qt.LinkAction ? "Link in " : root.action === Qt.CopyAction ? "Copy into " : "Into ") + root.name
            color: Colors.onAccent
            font.pixelSize: Tokens.font.small
            font.bold: true
            font.family: Properties.fontFamily
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            maximumLineCount: 1
        }
    }
}
