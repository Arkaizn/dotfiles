import QtQuick
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat

// One tile of the grid view: a big icon, the name under it (two lines).
// Clicks go to FolderView's pointer area underneath (onBody: on the icon / name?).
Item {
    id: tile

    required property int index
    required property string name
    required property bool dir
    required property string type
    required property bool hidden
    required property bool link
    required property bool exec
    required property bool broken
    property string glyph: ""            // a special folder's own glyph (Downloads, Desktop …), "" = by type
    required property string key
    required property real size
    required property real mtime
    required property bool ro

    property bool current: false          // the cursor (keys move from here)
    property bool selected: false
    property bool faded: false            // cut, waiting to be pasted
    property bool dropTarget: false       // a drag is over this folder: it goes in here
    property int iconSize: 64
    property int count: -1               // a folder: the items in it
    property string thumb: ""            // a thumbnail's URL ("" = the glyph)
    property string caption: "none"      // a line under the name: size | date | type

    readonly property var item: ({ dir: dir, type: type, exec: exec, broken: broken })

    Accessible.role: Accessible.ListItem
    Accessible.name: name
    Accessible.selected: selected

    Rectangle {
        anchors.fill: parent
        anchors.margins: Tokens.space.s2
        radius: Tokens.radius.xl
        color: tile.selected ? Colors.alpha(Colors.accent, 0.2) : hover.hovered ? Colors.fade(0.05) : "transparent"
        border.width: tile.dropTarget ? Tokens.border.selected : tile.current && !tile.selected ? Tokens.border.thin : 0
        border.color: tile.dropTarget ? Colors.accent : Colors.alpha(Colors.accent, 0.5)
        Behavior on color { ColorAnimation { duration: Anim.instant } }
    }
    HoverHandler { id: hover }
    // the icon and the name under it (the margin around them starts a rubber band)
    function onBody(x, y) {
        return x >= body.x && x <= body.x + body.width && y >= body.y && y <= body.y + body.implicitHeight + Tokens.space.s4
    }

    Column {
        id: body
        anchors.top: parent.top
        anchors.topMargin: Tokens.space.s8
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * Tokens.space.s6
        spacing: Tokens.space.s4
        opacity: tile.faded ? Tokens.alpha.dragged : tile.hidden ? 0.6 : 1
        Behavior on opacity { NumberAnimation { duration: Anim.normal } }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: tile.iconSize
            height: tile.iconSize
            Image {
                id: pic
                anchors.fill: parent
                source: tile.thumb
                sourceSize: Qt.size(tile.iconSize * 2, tile.iconSize * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Anim.normal } }
            }
            Text {
                visible: pic.status !== Image.Ready
                anchors.centerIn: parent
                text: tile.glyph || FmIcons.item(tile.item)
                color: tile.broken ? Colors.danger : tile.dir ? Colors.accent : Colors.fade(0.6)
                font.pixelSize: tile.iconSize
                font.family: Properties.fontFamily
            }
            Text {
                visible: tile.ro && !tile.broken
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: FmIcons.g.lock
                color: Colors.warning
                font.pixelSize: Math.max(Tokens.font.small, tile.iconSize * 0.3)
                font.family: Properties.fontFamily
            }
            Text {
                visible: tile.link && !tile.broken
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: FmIcons.g.link
                color: Colors.ink
                font.pixelSize: Math.max(Tokens.font.small, tile.iconSize * 0.3)
                font.family: Properties.fontFamily
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: FmFormat.shown(tile.name)
            color: tile.selected ? Colors.ink : Colors.fade(0.85)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: tile.selected && tile.current ? 4 : 2
            elide: Text.ElideRight            // (the only elide Qt does over several lines)
        }
        Text {
            visible: tile.caption !== "none"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: tile.caption === "size" ? (tile.dir ? (tile.count >= 0 ? FmFormat.items(tile.count) : "") : Format.bytes(tile.size))
                : tile.caption === "date" ? FmFormat.when(tile.mtime, Date.now())
                : tile.caption === "type" ? FmFormat.typeLabel(tile.item) : ""
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
    }
}
