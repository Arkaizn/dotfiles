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
    implicitWidth: trayRow.width + 8

    property bool hovered: false

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

    RowLayout {
        id: trayRow
        anchors.centerIn: parent
        spacing: 0

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

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu || modelData.onlyMenu) {
                                var globalPos = delegateItem.mapToItem(null, 0, delegateItem.height + 4)
                                customTrayMenu.openFor(modelData, globalPos.x, globalPos.y)
                            }
                            return
                        }

                        if (mouse.button === Qt.MiddleButton) {
                            if (modelData.secondaryActivate)
                                modelData.secondaryActivate()
                            return
                        }

                        if (modelData.onlyMenu && modelData.hasMenu) {
                            var globalPos = trayButton.mapToItem(Properties.contentItem, 0, 0)
                            modelData.display(
                                bar,
                                globalPos.x,
                                globalPos.y + trayButton.height + 4
                            )
                        } else {
                            modelData.activate()
                        }
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