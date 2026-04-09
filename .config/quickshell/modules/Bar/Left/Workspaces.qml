import Quickshell.Hyprland
import QtQuick
import qs.services
import qs.components

Rectangle {
    id:root
    implicitWidth: row.implicitWidth
    implicitHeight: bar.buttonHeight
    radius: bar.buttonradius


    gradient: ButtonGradient {
    }
    ButtonBackground {
        id: buttonBackground
    }

    Row {
        id: row
        spacing: 0
        leftPadding: 10
        rightPadding: 10

        Repeater {
            model: Hyprland.workspaces.values

            Rectangle {
                required property HyprlandWorkspace modelData

                color: Qt.rgba(0, 0, 0, 0)

                implicitHeight: bar.buttonHeight
                implicitWidth: text.implicitWidth + 10

                

                property bool hovered: workspaceMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    color: "transparent" // for testing -> Qt.rgba(0, 0, 0, modelData.id === Hyprland.focusedWorkspace?.id ? 0 : 0)
                    scale: modelData.id === Hyprland.focusedWorkspace?.id ? bar.onEnteredTextScale : bar.onExitedTextScale


                    Text {
                        id: text
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: bar.pixelSize
                        text: modelData.name
                        color: Colors.foreground
                        opacity: modelData.id === Hyprland.focusedWorkspace?.id ? 1.0 : 0.5
                    }
                }

                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()

                    onEntered: modelData.id === Hyprland.focusedWorkspace?.id ? 1 : parent.scale = bar.onEnteredTextScale
                    onExited: parent.scale = bar.onExitedTextScale
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: bar.bDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
