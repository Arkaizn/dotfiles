import Quickshell.Hyprland
import QtQuick
import qs.services
import qs.components

Item {
    id:root
    implicitWidth: row.implicitWidth
    implicitHeight: Properties.buttonHeight

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

                implicitHeight: Properties.buttonHeight
                implicitWidth: text.implicitWidth + 10

                

                property bool hovered: workspaceMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    color: "transparent" // for testing -> Qt.rgba(0, 0, 0, modelData.id === Hyprland.focusedWorkspace?.id ? 0 : 0)
                    scale: modelData.id === Hyprland.focusedWorkspace?.id ? Properties.onEnteredTextScale : Properties.onExitedTextScale


                    Text {
                        id: text
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Properties.pixelSize
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

                    onEntered: modelData.id === Hyprland.focusedWorkspace?.id ? 1 : parent.scale = Properties.onEnteredTextScale
                    onExited: parent.scale = Properties.onExitedTextScale
                }
                // needs to be here for the individual workspace hover
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
