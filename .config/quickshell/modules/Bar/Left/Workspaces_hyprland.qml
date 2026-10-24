import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.services
import qs.components

Item {
    id:root
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
            // this bar's monitor only (like the niri version), no special
            // workspaces (scratchpads have negative ids), in order
            model: Array.from(Hyprland.workspaces.values)
                .filter(w => w.id > 0 && w.monitor?.name === ((QsWindow.window as QsWindow)?.screen?.name ?? ""))
                .sort((a, b) => a.id - b.id)

            Rectangle {
                id: ws
                required property HyprlandWorkspace modelData
                // shown on its monitor (the focused one is shown on the focused monitor)
                readonly property bool isActive: modelData.monitor?.activeWorkspace?.id === modelData.id

                color: Qt.rgba(0, 0, 0, 0)

                implicitHeight: root.vertical ? text.implicitHeight + 10 : PanelGeometry.barButtonHeight
                implicitWidth: root.vertical ? PanelGeometry.barButtonHeight : text.implicitWidth + 10

                

                property bool hovered: workspaceMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    color: "transparent" // for testing -> Qt.rgba(0, 0, 0, modelData.id === Hyprland.focusedWorkspace?.id ? 0 : 0)
                    // one binding for every state (active / hover / pressed)
                    scale: workspaceMouse.pressed ? Properties.onPressedButtonScale
                         : (ws.isActive || workspaceMouse.containsMouse) ? Properties.onEnteredTextScale
                         : Properties.onExitedTextScale
                    Behavior on scale {
                        NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic }
                    }


                    Text {
                        id: text
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Properties.pixelSize
                        text: modelData.name
                        color: Properties.color
                        opacity: ws.isActive ? 1.0 : 0.5
                    }
                }

                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()

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
