import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts


RowLayout {
    id: root
    spacing: 4

    Repeater {
        model: SystemTray.items

        delegate: Rectangle {
            id: trayButton
            radius: 8

            implicitHeight: bar.buttonHeight
            implicitWidth: bar.iconSize + bar.buttonWidth

            property bool hovered: ma.containsMouse

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: trayButton.hovered
                        ? Qt.rgba(1, 1, 1, 0.45)
                        : Qt.rgba(1, 1, 1, 0.25)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(1, 1, 1, 0.15)
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 7
                color: Qt.rgba(0.12, 0.12, 0.12,
                            trayButton.hovered ? 0.30 : 0.18)

                IconImage {
                    anchors.centerIn: parent
                    width: bar.iconSize
                    height: bar.iconSize
                    source: modelData.icon
                }
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
                    // Right click: show context menu
                    if (mouse.button === Qt.RightButton) {
                        if (modelData.hasMenu || modelData.onlyMenu) {
                            // Calculate position relative to the bar window
                            var globalPos = trayButton.mapToItem(bar.contentItem, 0, 0)
                            modelData.display(
                                bar,
                                globalPos.x,
                                globalPos.y + trayButton.height + 4
                            )
                        }
                        return
                    }

                    // Middle click: secondary action
                    if (mouse.button === Qt.MiddleButton) {
                        if (modelData.secondaryActivate)
                            modelData.secondaryActivate()
                        return
                    }

                    // Left click: activate or show menu
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
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}