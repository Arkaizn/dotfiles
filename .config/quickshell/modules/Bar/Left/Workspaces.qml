import Quickshell.Hyprland
import QtQuick
import qs.services


Row {
    spacing: 6
    Repeater {
        model: Hyprland.workspaces.values

        Rectangle {
            required property HyprlandWorkspace modelData

            radius: 8
            
            implicitHeight: bar.buttonHeight
            implicitWidth: text.implicitWidth + bar.iconSize

            property bool hovered: workspaceMouse.containsMouse

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: modelData.id === Hyprland.focusedWorkspace?.id
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
                color: Qt.rgba(0.12, 0.12, 0.12, modelData.id === Hyprland.focusedWorkspace?.id ? 0.30 : 0.18)

                Text {
                    id: text
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: bar.pixelSize
                    text: modelData.name
                    color: modelData.id === Hyprland.focusedWorkspace?.id
                    ? Colors.color4 
                    : Colors.color6
                    opacity: modelData.id === Hyprland.focusedWorkspace?.id ? 1.0 : 0.5
                }
            }

            MouseArea {
                id: workspaceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.activate()

                onEntered: parent.scale = 1.08
                onExited: parent.scale = 1.0
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
