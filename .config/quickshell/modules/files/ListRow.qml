import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmColumns.js" as FmColumns

// One row of the list view: icon and name, then the chosen columns (size,
// modified, type, permissions). The roles come from FmFolder's model; the
// columns and their widths from FolderView. Clicks go to FolderView's pointer
// area underneath (it asks onBody whether a press is on the item: anywhere on a row).
Rectangle {
    id: row

    required property int index
    required property string name
    required property bool dir
    required property real size
    required property real mtime
    required property string type
    required property bool hidden
    required property bool link
    required property bool exec
    required property bool broken
    property string glyph: ""            // a special folder's own glyph (Downloads, Desktop …), "" = by type
    required property int mode
    required property string key
    required property string loc
    required property bool ro
    required property string owner
    required property string group

    property bool current: false          // the cursor (keys move from here)
    property bool selected: false
    property bool faded: false            // cut, waiting to be pasted
    property bool dropTarget: false       // a drag is over this folder: it goes in here
    property int iconSize: 20
    property var cols: ({})              // id → width, for the columns shown
    property var colIds: []              // their order
    property int count: -1               // a folder: the items in it (-1 = not counted)
    property string thumb: ""            // a thumbnail's URL ("" = the glyph)
    property string here: ""             // search results: the searched folder's name (for loc "")
    property real now: Date.now()

    readonly property var item: ({ dir: dir, type: type, exec: exec, broken: broken })

    implicitHeight: Math.max(iconSize, Tokens.font.body) + Tokens.space.s12
    radius: Tokens.radius.lg
    color: dropTarget ? Colors.alpha(Colors.accent, 0.3) : selected ? Colors.alpha(Colors.accent, 0.2) : hover.hovered ? Colors.fade(0.05) : "transparent"
    // the cursor on something unselected (after Ctrl+click): a thin ring
    border.width: dropTarget ? Tokens.border.selected : current && !selected ? Tokens.border.thin : 0
    border.color: dropTarget ? Colors.accent : Colors.alpha(Colors.accent, 0.5)
    Behavior on color { ColorAnimation { duration: row.dropTarget ? Anim.fast : Anim.instant } }
    Accessible.role: Accessible.ListItem
    Accessible.name: name
    Accessible.selected: selected

    HoverHandler { id: hover }
    // the icon and the name's text (not the empty room after it, where a rubber band starts)
    // the whole row is the item: a press anywhere on it drags it (a rubber band starts from the
    // empty space below the rows)
    function onBody(x, y) { return true }

    function cell(id) {
        switch (id) {
        case "size": return row.dir ? (row.count >= 0 ? FmFormat.items(row.count) : "—") : Format.bytes(row.size)
        case "loc": return FmFormat.shown(row.loc === "" ? row.here : row.loc)
        case "mtime": return FmFormat.when(row.mtime, row.now)
        case "type": return FmFormat.typeLabel(row.item)
        case "perms": return FmColumns.perms(row.mode)
        case "owner": return row.owner
        case "group": return row.group
        }
        return ""
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s10
        anchors.rightMargin: Tokens.space.s10
        spacing: Tokens.space.s10
        opacity: row.faded ? Tokens.alpha.dragged : row.hidden ? 0.6 : 1
        Behavior on opacity { NumberAnimation { duration: Anim.normal } }

        Item {
            implicitWidth: row.iconSize
            implicitHeight: row.iconSize
            scale: row.dropTarget ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.pop } }
            Image {
                id: pic
                anchors.fill: parent
                source: row.thumb
                sourceSize: Qt.size(row.iconSize * 2, row.iconSize * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Anim.normal } }
            }
            Text {
                visible: pic.status !== Image.Ready
                anchors.centerIn: parent
                text: row.dropTarget && row.dir ? FmIcons.g.folderOpen : row.glyph || FmIcons.item(row.item)
                color: row.broken ? Colors.danger : row.dir ? Colors.accent : Colors.fade(0.6)
                font.pixelSize: row.iconSize
                font.family: Properties.fontFamily
            }
            // can't be changed: a lock in the other corner
            Text {
                visible: row.ro && !row.broken
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: -Tokens.space.s2
                text: FmIcons.g.lock
                color: Colors.warning
                font.pixelSize: Math.max(Tokens.font.micro, row.iconSize * 0.45)
                font.family: Properties.fontFamily
            }
            // a link: a small arrow in the corner
            Text {
                visible: row.link && !row.broken
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -Tokens.space.s2
                text: FmIcons.g.link
                color: Colors.ink
                font.pixelSize: Math.max(Tokens.font.micro, row.iconSize * 0.45)
                font.family: Properties.fontFamily
            }
        }
        Text {
            id: nameText
            Layout.fillWidth: true
            text: FmFormat.shown(row.name)
            color: row.selected ? Colors.ink : Colors.fade(0.85)
            font.pixelSize: Tokens.font.body
            font.family: Properties.fontFamily
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            maximumLineCount: 1
        }
        Repeater {
            model: row.colIds
            Text {
                required property string modelData
                Layout.preferredWidth: row.cols[modelData] ?? 0
                horizontalAlignment: FmColumns.spec(modelData)?.right ? Text.AlignRight : Text.AlignLeft
                text: row.cell(modelData)
                color: Colors.fade(0.5)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
    }
}
