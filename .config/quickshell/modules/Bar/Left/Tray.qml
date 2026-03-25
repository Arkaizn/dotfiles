import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs.services

Rectangle {
    id: trayButton
    radius: 8
    implicitHeight: bar.buttonHeight
    implicitWidth: trayRow.width + 8
    property bool hovered: trayHoverHandler.containsMouse

    gradient: ButtonGradient {
        hovered: trayButton.hovered
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12,
            trayButton.hovered ? 0.30 : 0.18)
    }

    HoverHandler {
        id: trayHoverHandler
    }

    RowLayout {
        id: trayRow
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: trayButton
                implicitHeight: bar.iconSize
                implicitWidth: bar.iconSize + bar.buttonWidth

                property bool hovered: ma.containsMouse

                IconImage {
                    anchors.centerIn: parent
                    width: bar.iconSize
                    height: bar.iconSize
                    source: modelData.icon
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onEntered: trayButton.scale = 1.08
                    onExited: trayButton.scale = 1.0

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu || modelData.onlyMenu) {
                                var globalPos = trayButton.mapToItem(bar.contentItem, 0, 0)
                                modelData.display(
                                    bar,
                                    globalPos.x,
                                    globalPos.y + trayButton.height + 4
                                )
                            }
                            return
                        }

                        if (mouse.button === Qt.MiddleButton) {
                            if (modelData.secondaryActivate)
                                modelData.secondaryActivate()
                            return
                        }

                        if (modelData.onlyMenu && modelData.hasMenu) {
                            var globalPos = trayButton.mapToItem(bar.contentItem, 0, 0)
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

                Behavior on scale {
                    NumberAnimation {
                        duration: bar.bduration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}