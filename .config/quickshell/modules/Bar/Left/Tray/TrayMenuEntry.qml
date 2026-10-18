import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.services

// One row of a tray menu: separator, normal item, checkbox/radio item or
// submenu (› on the right). Styled like the control center / launcher rows.
Item {
    id: root

    property var entry: null
    signal activated()

    readonly property bool separator: entry?.isSeparator ?? false
    readonly property bool usable: !separator && (entry?.enabled ?? true)
    readonly property bool checkable: entry && entry.buttonType !== QsMenuButtonType.None
    readonly property bool checked: entry?.checkState === Qt.Checked

    implicitHeight: separator ? 9 : 32

    // separator line
    Rectangle {
        visible: root.separator
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
        height: 1
        color: Colors.fade(0.13)
    }

    Rectangle {
        visible: !root.separator
        anchors.fill: parent
        radius: 8
        color: mouse.containsMouse && root.usable ? Colors.fade(0.10) : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8

            // checkbox / radio state
            Text {
                visible: root.checkable
                text: root.entry?.buttonType === QsMenuButtonType.RadioButton
                    ? (root.checked ? "󰐾" : "󰄰")
                    : (root.checked ? "󰄵" : "󰄱")
                color: root.checked ? Colors.ink : Colors.fade(0.5)
                font.pixelSize: 14
                font.family: Properties.fontFamily
            }

            IconImage {
                visible: (root.entry?.icon ?? "") !== ""
                source: root.entry?.icon ?? ""
                implicitSize: 16
                opacity: root.usable ? 1 : 0.4
            }

            Text {
                Layout.fillWidth: true
                // DBus menus mark mnemonics with "_" — drop them
                text: (root.entry?.text ?? "").replace(/_(?=\S)/g, "")
                color: !root.usable ? Colors.fade(0.35)
                     : mouse.containsMouse ? Colors.ink : Colors.fade(0.85)
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                visible: root.entry?.hasChildren ?? false
                text: "󰅂"
                color: Colors.fade(0.5)
                font.pixelSize: 13
                font.family: Properties.fontFamily
            }
        }
    }
}
