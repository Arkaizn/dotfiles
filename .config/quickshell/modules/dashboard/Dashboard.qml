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
    readonly property int width: 1150
    readonly property int height: 500
    property bool hasBeenHovered: false
    property bool showCorners: false

    implicitWidth: width
    implicitHeight: height
    color: "transparent"
    exclusiveZone: 0
    property int bottomLeftRadius: 40
    property int bottomRightRadius: 40
    property int radius: 30

    BackgroundEffect.blurRegion: Region {
        item: rect
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
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
            cornerDelayTimer.stop()
            showCorners = false // animate corners out together with the panel
            anim.exit()
        } else {
            root.visible = true
            showCorners = false
            enterTimer.start()
        }
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: {
            anim.enter()
            cornerDelayTimer.start()
        }
    }

    Timer {
        id: cornerDelayTimer
        interval: 0 // corners start animating in 0.1s after the panel starts opening
        repeat: false
        onTriggered: {
            root.showCorners = true
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
        anchors.topMargin: root.showCorners ? 0 : -16
        corner: "topRight"
        color: rect.color
        radius: 40
        opacity: root.showCorners ? 1 : 0

        Behavior on anchors.topMargin {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
    InverseCorner {
        id: cornerright
        anchors.left: rect.right
        anchors.top: rect.top
        anchors.topMargin: root.showCorners ? 0 : -16
        corner: "topLeft"
        color: rect.color
        radius: 40
        opacity: root.showCorners ? 1 : 0

        Behavior on anchors.topMargin {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
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
            rightMargin: 40
            leftMargin: 40
        }
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
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
                radius: root.radius
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
                    radius: root.radius / 4 * 3
                    color: '#45000000'

                    DashboardMusic {}
                }

                // Calendar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.radius / 4 * 3
                    color: '#45000000'

                    DashboardCalendar {}
                }
            }

            // RIGHT — System stats
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 300
                radius: root.radius
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