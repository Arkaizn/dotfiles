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

// Dashboard: profile, music, calendar, system stats.
// Window/shape/animation all come from BarPopup.
BarPopup {
    id: root
    side: "center"
    ipcName: "dashboard"
    panelWidth: 1070
    panelHeight: 480
    // inner cards: panel radius minus the padding, so the corners nest concentrically
    property int radius: Properties.panelRadius - padding

    RowLayout {
        anchors.fill: parent
        spacing: 10

        // LEFT — User stats
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 300
            radius: root.radius
            color: '#45000000'
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder

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
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder

                DashboardMusic {}

                // The album-art background fills this card and would cover its
                // border, so draw the outline again on top.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: Properties.panelBorderWidth
                    border.color: Properties.cardBorder
                }
            }

            // Calendar
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.radius / 4 * 3
                color: '#45000000'
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder

                // month grid + the picked day's events (when the calendar app has accounts)
                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    readonly property bool hasEvents: CalendarStore.accounts.length > 0

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        DashboardCalendar { id: dashCal }
                    }
                    Rectangle {
                        visible: parent.hasEvents
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 14
                        Layout.bottomMargin: 14
                        color: Properties.cardBorder
                    }
                    DashboardEvents {
                        visible: parent.hasEvents
                        Layout.fillHeight: true
                        Layout.preferredWidth: Math.round(parent.width * 0.40)
                        day: dashCal.selectedDate
                    }
                }
            }
        }

        // RIGHT — System stats
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 300
            radius: root.radius
            color: '#45000000'
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder

            DashboardStats {}
        }
    }
}
