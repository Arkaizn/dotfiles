import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: trayMenu

    property var trayItem: null
    property int menuX: 0
    property int menuY: 0

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function openFor(item, x, y) {
        trayItem = item
        menuX = x
        menuY = y
        visible = true
    }

    function close() {
        visible = false
        trayItem = null
    }

    QsMenuOpener {
        id: menuOpener
        menu: trayMenu.trayItem ? trayMenu.trayItem.menu : null
    }

    MouseArea {
        anchors.fill: parent
        onClicked: trayMenu.close()
        z: 0
    }

    Rectangle {
        id: menuRect
        x: trayMenu.menuX
        y: trayMenu.menuY
        implicitWidth: col.implicitWidth + 16
        implicitHeight: col.implicitHeight + 16
        radius: 10
        color: Qt.rgba(0.10, 0.10, 0.10, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        z: 1

        ColumnLayout {
            id: col
            anchors {
                top: parent.top
                left: parent.left
                margins: 8
            }
            spacing: 2

            Repeater {
                model: menuOpener.children
                delegate: MenuEntry {
                    required property var modelData
                    entry: modelData
                    onClicked: trayMenu.close()
                }
            }
        }
    }
}