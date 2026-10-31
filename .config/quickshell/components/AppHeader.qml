import QtQuick
import QtQuick.Layouts
import qs.services

// The head of an app's content: an optional overline ("Mail ›"), the page
// title, a line under it, and the page's buttons on the right (they stay at
// the right edge on every page). Dragging it moves the window. Grows when the
// subtitle wraps (narrow window).
//
//   AppHeader {
//       overline: "Maintenance"; title: "Updates"; subtitle: "Pending updates, …"
//       ActionButton { text: "Today" }  IconButton { icon: "󰅖"; tooltip: "Close" }
//   }
//   leading: a back button left of the texts (optional, `leading: [backBtn]` or as child of `lead`)
Item {
    id: root
    property string overline: ""
    property string title: ""
    property string subtitle: ""
    property bool wrapSubtitle: true
    default property alias actions: actionRow.data
    property alias lead: leadRow.data
    property alias titleItem: titleBlock

    Layout.fillWidth: true
    implicitHeight: Math.max(56, row.implicitHeight)
    Accessible.role: Accessible.Heading
    Accessible.name: title

    DragHandler {
        target: null
        onActiveChanged: if (active) root.Window.window.startSystemMove()
    }
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.space.s6
        spacing: Tokens.space.s8

        RowLayout { id: leadRow; spacing: Tokens.space.s6; visible: children.length > 0 }

        // the texts fill the width (a layout is only as wide as its children let
        // it be): the buttons on the right stay at the right edge
        ColumnLayout {
            id: titleBlock
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0
            Text {
                visible: root.overline !== ""
                Layout.fillWidth: true
                text: root.overline + "  ›"
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.title
                color: Colors.ink
                font.pixelSize: Tokens.font.page
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                text: root.subtitle
                color: Colors.fade(0.5)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                wrapMode: root.wrapSubtitle ? Text.Wrap : Text.NoWrap
                elide: root.wrapSubtitle ? Text.ElideNone : Text.ElideRight
            }
        }
        RowLayout { id: actionRow; spacing: Tokens.space.s8 }
    }
}
