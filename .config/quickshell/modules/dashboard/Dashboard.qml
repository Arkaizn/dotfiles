import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import "."

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
    }
    readonly property int width: 1120
    readonly property int height: 500
    property bool hasBeenHovered: false

    implicitWidth: width
    implicitHeight: height
    color: "transparent"
    exclusiveZone: 0

    BackgroundEffect.blurRegion: Region {
        item: rect
        bottomLeftRadius: 12
        bottomRightRadius: 12
    }

    

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
        enterDuration: 150
        exitDuration: 150
        onExitFinished: root.visible = false
    }



    function toggle() {
        if (root.visible) {
            anim.exit()
        } else {
            root.visible = true
            enterTimer.start()
        }
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: {
            anim.enter()
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 500
        repeat: false
        onTriggered: {
            anim.exit()
            hasBeenHovered = false
        }
    }

    InverseCorner {
        id: cornerleft
        anchors.right: rect.left
        anchors.top: rect.top
        corner: "topRight"
        color: rect.color
        radius: 12
    }
    InverseCorner {
        anchors.left: rect.right
        anchors.top: rect.top
        corner: "topLeft"
        color: rect.color
        radius: 12
    }

    Rectangle {
        id: rect
        implicitHeight: parent.height - 20
        clip: true
        opacity: 0
        y: -height
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            rightMargin: 10
            leftMargin: 10
        }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        RowLayout {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                // top: parent.top  // remove this if you have it
                margins: 10
            }
            height: rect.implicitHeight - 20  // fixed height, not dependent on animated height
            spacing: 10

            // LEFT — User stats
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 300
                radius: 12
                color: '#45000000'

                DashboardProfile {}
            }

            // MIDDLE — Music player (top) + Calendar (bottom)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Music player
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    radius: 12
                    color: '#45000000'

                    DashboardMusic {}
                }

                // Calendar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: '#45000000'

                    DashboardCalendar {}
                }
            }

            // RIGHT — System stats
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 300
                radius: 12
                color: '#45000000'

                DashboardStats {}
            }
        }
        HoverHandler {
            id: rectHover
            onHoveredChanged: {
                if (hovered) {
                    hasBeenHovered = true
                    autoCloseTimer.stop()
                } else if (hasBeenHovered) {
                    autoCloseTimer.start()
                }
            }
        }
    }
}