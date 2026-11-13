import QtQuick
import QtQuick.Layouts
import qs.services

// The app's name at the top of its sidebar (mail, calendar, settings) or of
// its page (perfmon): accent icon + bold name, optional line below, optional
// buttons on the right. Dragging it moves the window.
//
//   AppTitle { icon: "󰃭"; title: "Calendar" }
//   AppTitle { icon: "󰒓"; title: "Settings"; IconButton { … } IconButton { … } }
//   AppTitle { icon: "󰓅"; title: "Performance"; subtitle: cpuName }
Item {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    implicitHeight: 44
    Accessible.role: Accessible.TitleBar
    Accessible.name: title

    DragHandler {
        target: null
        onActiveChanged: if (active) root.Window.window.startSystemMove()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s4
        spacing: Tokens.space.s10
        Text {
            text: root.icon
            color: Colors.accent
            font.pixelSize: Tokens.font.headline
            font.family: Properties.fontFamily
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: root.title
                color: Colors.ink
                font.pixelSize: Tokens.font.title
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                text: root.subtitle
                color: Colors.textMuted
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
        RowLayout { id: actionRow; spacing: Tokens.space.s6 }
    }
}
