import QtQuick
import Quickshell
import qs.components
import QtQuick.Layouts
import "."

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
    }
    implicitWidth: 800
    implicitHeight: 400
    color: "transparent"
    exclusiveZone: 0

    function toggle() {
        root.visible = !root.visible
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
        anchors {
            fill: parent
            rightMargin: 10
            leftMargin: 10
            bottomMargin: 10
        }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
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