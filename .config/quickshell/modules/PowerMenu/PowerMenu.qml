import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QsServices

PanelWindow {
    id: root
    required property int barHeight
    property var modelData
    screen: modelData
    anchors {
        top: true
        left: true
    }

    function startTimer() {
        graceTimer.start();
    }

    property bool shouldBeVisible: {
        return FoldOutManager.isOpen("powermenu") && FoldOutManager.getScreenName("powermenu") === root.screen.name;
    }

    visible: shouldBeVisible
    implicitHeight: barHeight
    implicitWidth: 24 * 8
    exclusiveZone: barHeight
    color: "transparent"

    Component.onCompleted: {
        FoldOutManager.registerFoldout("powermenu");
    }

    Process {
        id: processHandler
    }

    property var menuModel: [
        {
            icon: "\udb81\udc25",
            cmd: ["systemctl", "poweroff"]
        },
        {
            icon: "\udb81\udf09",
            cmd: ["reboot"]
        },
        {
            icon: "\udb81\udcb2",
            cmd: ["systemctl", "suspend"]
        },
        {
            icon: "\udb80\udf41",
            cmd: ["hyprlock"]
        },
    ]

    Rectangle {
        id: menu
        y: 0
        clip: true
        color: "#1a1a1a"
        height: root.shouldBeVisible ? root.barHeight : 0
        width: 24 * 8
        bottomRightRadius: 16

        Behavior on height {
            NumberAnimation {
                duration: 250
                easing.type: Easing.InOutCirc
            }
        }

        Timer {
            id: graceTimer
            interval: 500
            onTriggered: {
                var triggerHovered = FoldOutManager.isTriggerHovered("powermenu", root.screen.name);
                if (!menuMouseArea.containsMouse && !triggerHovered) {
                    FoldOutManager.toggle("powermenu", root.screen.name, false);
                }
            }
        }

        MouseArea {
            id: menuMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                FoldOutManager.toggle("powermenu", root.screen.name, true);
            }
            onExited: {
                graceTimer.start();
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 24
            Repeater {
                model: root.menuModel
                delegate: Text {
                    text: modelData.icon
                    color: "#ffffff"
                    font {
                        family: "JetBrainsMono Nerd Font Mono"
                        pixelSize: 28
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            processHandler.exec(modelData.cmd);
                            FoldOutManager.toggle("powermenu", root.screen.name, false);
                        }
                    }
                }
            }
        }
    }
}
