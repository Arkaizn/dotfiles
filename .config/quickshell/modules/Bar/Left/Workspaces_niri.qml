import Quickshell
import QtQuick
import qs.services
import qs.components

Item {
    id: root
    // a row; a column on a left / right bar (Part 6.7)
    readonly property bool vertical: PanelGeometry.barVertical
    implicitWidth: vertical ? PanelGeometry.barButtonHeight : row.implicitWidth
    implicitHeight: vertical ? row.implicitHeight : PanelGeometry.barButtonHeight

    ButtonBackground {
        id: buttonBackground
    }
    Grid {
        id: row
        columns: root.vertical ? 1 : 999
        spacing: 0
        leftPadding: root.vertical ? 0 : 10
        rightPadding: root.vertical ? 0 : 10
        topPadding: root.vertical ? 8 : 0
        bottomPadding: root.vertical ? 8 : 0
        Repeater {
            model: NiriIpc.workspaces
            Rectangle {
                // Only show workspaces that belong to this bar's monitor
                visible: model.output === ((QsWindow.window as QsWindow)?.screen?.name ?? "")
                color: Qt.rgba(0, 0, 0, 0)
                implicitHeight: !visible ? 0 : root.vertical ? text.implicitHeight + 10 : PanelGeometry.barButtonHeight
                implicitWidth: !visible ? 0 : root.vertical ? PanelGeometry.barButtonHeight : text.implicitWidth + 10
                property bool hovered: workspaceMouse.containsMouse
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    // one binding for every state — the old onEntered/onExited assignments
                    // overwrote this, so the active workspace lost its size after a hover
                    scale: workspaceMouse.pressed ? Properties.onPressedButtonScale
                         : (model.isActive || workspaceMouse.containsMouse) ? Properties.onEnteredTextScale
                         : Properties.onExitedTextScale
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
                        onClicked: NiriIpc.focusWorkspaceById(model.id)
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