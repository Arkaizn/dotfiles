import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.DBusMenu
import Quickshell.Widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

import ".."

PanelWindow {
            id: bar

            property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            margins.top: 8
            margins.left: 8
            margins.right: 8
            color: "transparent"

            implicitHeight: 45
            exclusiveZone: height + margins.top
            aboveWindows: true
            focusable: false

            Rectangle {
                id: mainShape
                anchors.fill: parent
                radius: 12

                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.color2 }
                    GradientStop { position: 1.0; color: Colors.color1 }
                    orientation: Gradient.Vertical
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: '#cb000000'
                radius: 10
            }

        }