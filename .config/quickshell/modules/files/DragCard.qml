import QtQuick
import qs.services

// What the pointer carries while files are dragged (FolderView grabs it into
// the drag's image): the first item's icon or thumbnail and its name on a
// card; for several, cards stacked behind it and a count badge.
//   DragCard { glyph; glyphColor; thumb; name; count }
Item {
    id: root

    property string glyph: ""
    property color glyphColor: Colors.accent
    property string thumb: ""            // a thumbnail / theme icon URL ("" = the glyph)
    property string name: ""
    property int count: 1
    readonly property bool ready: thumb === "" || pic.status !== Image.Loading

    readonly property real pad: Tokens.space.s8
    // the badge sticks out over the card's top-right corner by half its size
    readonly property real bw: count > 1 ? badge.width : 0
    readonly property real bh: count > 1 ? badge.height : 0
    readonly property real stack: count > 1 ? Tokens.space.s4 * Math.min(count - 1, 2) : 0
    width: Math.min(Tokens.size.row * 6, Math.max(Tokens.size.row * 3, label.implicitWidth + Tokens.icon.lg + 3 * pad)) + stack + bw / 2
    height: Tokens.icon.lg + 2 * pad + stack + bh / 2

    // the cards behind (two at most), each a little lower right
    Repeater {
        model: Math.min(root.count - 1, 2)
        Rectangle {
            required property int index
            x: root.stack - Tokens.space.s4 * index
            y: root.bh / 2 + root.stack - Tokens.space.s4 * index
            width: card.width
            height: card.height
            radius: Tokens.radius.lg
            color: Colors.surfacePopover
            border.width: Tokens.border.thin
            border.color: Colors.lineSubtle
            opacity: 0.7 - 0.2 * index
        }
    }
    Rectangle {
        id: card
        x: 0
        y: root.bh / 2
        width: root.width - root.stack - root.bw / 2
        height: Tokens.icon.lg + 2 * root.pad
        radius: Tokens.radius.lg
        color: Colors.surfacePopover
        border.width: Tokens.border.thin
        border.color: Colors.alpha(Colors.accent, 0.5)

        Item {
            id: icon
            x: root.pad
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.icon.lg
            height: Tokens.icon.lg
            Image {
                id: pic
                anchors.fill: parent
                source: root.thumb
                sourceSize: Qt.size(Tokens.icon.lg * 2, Tokens.icon.lg * 2)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }
            Text {
                visible: !pic.visible
                anchors.centerIn: parent
                text: root.glyph
                color: root.glyphColor
                font.pixelSize: Tokens.icon.lg
                font.family: Properties.fontFamily
            }
        }
        Text {
            id: label
            anchors.left: icon.right
            anchors.leftMargin: root.pad
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            text: root.name
            color: Colors.ink
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            maximumLineCount: 1
        }
    }
    // how many (several only)
    Rectangle {
        id: badge
        visible: root.count > 1
        anchors.right: card.right
        anchors.rightMargin: -width / 2
        y: 0
        width: Math.max(height, num.implicitWidth + 2 * Tokens.space.s6)
        height: Tokens.font.small + Tokens.space.s8
        radius: height / 2
        color: Colors.accent
        Text {
            id: num
            anchors.centerIn: parent
            text: root.count
            color: Colors.onAccent
            font.pixelSize: Tokens.font.caption
            font.bold: true
            font.family: Properties.fontFamily
        }
    }
}
