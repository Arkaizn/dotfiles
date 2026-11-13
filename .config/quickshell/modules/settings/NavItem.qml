import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Sidebar entry: icon + label, gradient when selected/hovered, and a small
// counter of changed values on the right. Sub-pages (Mail › Reading …): small,
// an icon tint (an account's color), dim (a button like Add account); a page with
// sub-pages: arrow (0 folded, 1 open, -1 none). slideHighlight: the selected look
// comes from one highlight that slides between the items (the settings window's
// sidebar), the item itself only shows hover.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property bool selected: false
    property int changes: 0
    property bool small: false
    property string tint: ""
    property bool dim: false
    property int arrow: -1
    property bool slideHighlight: false
    signal clicked()

    implicitHeight: Properties.buttonHeight + 4
    // with the sliding highlight only the content reacts to a press (the highlight stays put)
    scale: slideHighlight ? 1 : mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

    Rectangle {
        id: face
        readonly property bool own: root.selected && !root.slideHighlight
        anchors.fill: parent
        radius: Tokens.radius.lg
        border.width: face.own || mouse.containsMouse ? 1.5 : 0
        border.color: Colors.line(face.own ? 0.24 : 0.14)
        gradient: ButtonGradient { hovered: face.own }
        opacity: face.own ? 1 : mouse.containsMouse && !root.selected ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: Anim.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s10
        scale: root.slideHighlight && mouse.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
        anchors.rightMargin: Tokens.space.s10
        spacing: Tokens.space.s10

        Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.tint !== "" ? root.tint : root.selected ? Colors.color6 : Colors.fade(root.dim ? 0.45 : 0.6)
            font.pixelSize: root.small ? 14 : 16
            font.family: Properties.fontFamily
            Behavior on color { ColorAnimation { duration: Anim.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.selected ? Colors.ink : Colors.fade(root.dim ? 0.5 : 0.75)
            Behavior on color { ColorAnimation { duration: Anim.normal } }
            font.pixelSize: root.small ? 12 : 13
            font.bold: root.selected
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Rectangle {
            visible: root.changes > 0
            implicitWidth: Math.max(18, count.implicitWidth + 10)
            implicitHeight: 18
            radius: 9
            color: Colors.fade(0.1)
            Text {
                id: count
                anchors.centerIn: parent
                text: root.changes
                color: Colors.color6
                font.pixelSize: Tokens.font.micro
                font.bold: true
                font.family: Properties.fontFamily
            }
        }
        // fold arrow, turns when the sub-pages open
        Text {
            visible: root.arrow >= 0
            text: "󰅂"
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            rotation: root.arrow === 1 ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
