import QtQuick
import Quickshell
import qs.components
import qs.services
import QtQuick.Layouts
import "."

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
    }
    readonly property int width: 800
    readonly property int height: 400

    implicitWidth: width
    implicitHeight: height
    color: "transparent"
    exclusiveZone: 0


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
            anim.enter()
        }
    }

    InverseCorner {
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
    opacity: 1
    anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        rightMargin: 10
        leftMargin: 10
    }
    // NO bottom anchor, NO anchors.fill
    
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
                Layout.preferredWidth: 160
                radius: 12
                color: '#45000000'

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Text { text: "👤 user"; color: "white"; font.bold: true }
                    Text { text: "Arch Linux 6.9.3"; color: "#aaaaaa"; font.pixelSize: 11 }
                    Text { text: "1,482 packages"; color: "#aaaaaa"; font.pixelSize: 11 }
                }
            }

            // MIDDLE — Music player (top) + Calendar (bottom)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Music player
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    radius: 12
                    color: '#45000000'

                    Text {
                        anchors.centerIn: parent
                        text: "🎵 Music Player"
                        color: "white"
                    }
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
                Layout.preferredWidth: 160
                radius: 12
                color: '#45000000'

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Text { text: "CPU  42°C  23%"; color: "white"; font.pixelSize: 11 }
                    Text { text: "GPU  61°C  40%"; color: "white"; font.pixelSize: 11 }
                    Text { text: "RAM  6.2 / 16 GB"; color: "white"; font.pixelSize: 11 }
                }
            }
        }
    }
}