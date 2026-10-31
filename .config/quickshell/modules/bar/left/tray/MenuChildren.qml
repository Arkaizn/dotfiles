import QtQuick
import qs.services
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: childCol
    property var parentEntry
    signal clicked()

    implicitWidth: col.implicitWidth + 16
    implicitHeight: col.implicitHeight + 16
    radius: Tokens.radius.lg
    color: Colors.surfacePopover
    border.color: Colors.lineSubtle
    border.width: 1

    QsMenuOpener {
        id: subOpener
        menu: parentEntry ?? null
    }

    ColumnLayout {
        id: col
        anchors {
            top: parent.top
            left: parent.left
            margins: Tokens.space.s8
        }
        spacing: Tokens.space.s2

        Repeater {
            model: subOpener.children
            delegate: Loader {
                required property var modelData
                source: Qt.resolvedUrl("MenuEntry.qml")
                onLoaded: {
                    item.entry = modelData
                    item.clicked.connect(childCol.clicked)
                }
            }
        }
    }
}