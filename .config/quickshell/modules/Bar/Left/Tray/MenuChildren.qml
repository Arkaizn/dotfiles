import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: childCol
    property var parentEntry
    signal clicked()

    implicitWidth: col.implicitWidth + 16
    implicitHeight: col.implicitHeight + 16
    radius: 10
    color: Qt.rgba(0.10, 0.10, 0.10, 0.92)
    border.color: Qt.rgba(1, 1, 1, 0.10)
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
            margins: 8
        }
        spacing: 2

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