import QtQuick
import qs.services
import qs.components
Rectangle {
    id: root
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
            model: niri.workspaces
            Rectangle {
                // Only show workspaces that belong to this bar's monitor
                visible: model.output === bar.screen.name
                color: Qt.rgba(0, 0, 0, 0)
                implicitHeight: visible ? bar.buttonHeight : 0
                implicitWidth: visible ? text.implicitWidth + 10 : 0
                property bool hovered: workspaceMouse.containsMouse
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    scale: model.isActive ? bar.onEnteredTextScale : bar.onExitedTextScale
                    Text {
                        id: text
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: bar.pixelSize
                        text: model.name || model.index
                        color: Colors.foreground
                        opacity: model.isActive ? 1.0 : 0.5
                    }
                    MouseArea {
                        id: workspaceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: niri.focusWorkspaceById(model.id)
                        onEntered: if (!model.isActive) parent.scale = bar.onEnteredTextScale
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
}