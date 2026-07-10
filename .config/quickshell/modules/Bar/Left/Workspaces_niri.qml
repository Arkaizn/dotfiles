import QtQuick
import qs.services
import qs.components

Item {
    id: root
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
            model: niri.workspaces
            Rectangle {
                // Only show workspaces that belong to this bar's monitor
                visible: model.output === bar.screen.name
                color: Qt.rgba(0, 0, 0, 0)
                implicitHeight: visible ? Properties.buttonHeight : 0
                implicitWidth: visible ? text.implicitWidth + 10 : 0
                property bool hovered: workspaceMouse.containsMouse
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    scale: model.isActive ? Properties.onEnteredTextScale : Properties.onExitedTextScale
                    Text {
                        id: text
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Properties.pixelSize
                        text: model.name || model.index
                        color: Properties.color
                        opacity: model.isActive ? 1.0 : 0.5
                    }
                    MouseArea {
                        id: workspaceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: niri.focusWorkspaceById(model.id)
                        onEntered: if (!model.isActive) parent.scale = Properties.onEnteredTextScale
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
}