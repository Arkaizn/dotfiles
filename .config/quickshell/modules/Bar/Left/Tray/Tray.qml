import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Item {
    id: trayButton
    anchors.margins: 0.5
    implicitHeight: Properties.buttonHeight
    implicitWidth: toggle.width + itemsClip.width + 8

    property bool hovered: false
    // open = the tray's icons show; closed = only the toggle (Settings.bar.trayOpen)
    readonly property bool open: Settings.bar.trayOpen ?? true

    ButtonBackground {
        id: buttonBackground
    }

    visible: repeater.count > 0

    TrayMenu {
        id: customTrayMenu
    }
   
    HoverHandler {
        id: trayHoverHandler
    }

    // arrow: always there, opens / closes the tray
    Item {
        id: toggle
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Properties.iconSize
        implicitWidth: toggleRow.width + 8

        Row {
            id: toggleRow
            anchors.centerIn: parent
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅂"
                color: Properties.color
                font.family: Properties.fontFamily
                font.pixelSize: Properties.iconSize
                rotation: trayButton.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: toggle.scale = Properties.onEnteredTextScale
            onExited: toggle.scale = Properties.onExitedTextScale
            onPressed: toggle.scale = Properties.onPressedButtonScale
            onReleased: toggle.scale = containsMouse ? Properties.onEnteredTextScale : Properties.onExitedTextScale
            onCanceled: toggle.scale = Properties.onExitedTextScale
            onClicked: trayButton.open ? Settings.set("bar", "trayOpen", false) : Settings.reset("bar", "trayOpen")
        }
        Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
    }

    // the tray's icons, slid in / out next to the toggle
    Item {
        id: itemsClip
        anchors.left: toggle.right
        anchors.verticalCenter: parent.verticalCenter
        height: trayRow.height
        width: trayButton.open ? trayRow.width : 0
        clip: true
        Behavior on width { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

        RowLayout {
            id: trayRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            opacity: trayButton.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Properties.bDuration } }

            Repeater {
                id:repeater
                model: SystemTray.items
                delegate: Item {
                    id: delegateItem
                    implicitHeight: Properties.iconSize
                    implicitWidth: Properties.iconSize + 10
                    

                    property bool hovered: ma.containsMouse

                    IconImage {
                        anchors.centerIn: parent
                        width: Properties.iconSize
                        height: Properties.iconSize
                        source: modelData.icon
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                        onEntered: delegateItem.scale = Properties.onEnteredTextScale
                        onExited: delegateItem.scale = Properties.onExitedTextScale
                        onPressed: delegateItem.scale = Properties.onPressedButtonScale
                        onReleased: delegateItem.scale = containsMouse ? Properties.onEnteredTextScale : Properties.onExitedTextScale
                        onCanceled: delegateItem.scale = Properties.onExitedTextScale

                        onClicked: function(mouse) {
                            // centre of this icon in screen coordinates (the bar spans the screen)
                            const centerX = delegateItem.mapToItem(null, delegateItem.width / 2, 0).x

                            if (mouse.button === Qt.MiddleButton) {
                                modelData.secondaryActivate()
                                return
                            }
                            // right click, or left click on menu-only apps → our menu
                            if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                                if (modelData.hasMenu)
                                    customTrayMenu.toggleFor(modelData, (QsWindow.window as QsWindow)?.screen, centerX)
                                return
                            }
                            modelData.activate()
                        }

                        onWheel: function(wheel) {
                            if (modelData.scroll)
                                modelData.scroll(wheel.angleDelta.y, false)
                        }
                    }

                    // needs to be here for the individial tray icon
                    Behavior on scale {
                        NumberAnimation {
                            duration: Properties.bDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
