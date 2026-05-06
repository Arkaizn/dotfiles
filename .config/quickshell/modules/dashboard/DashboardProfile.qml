import QtQuick
import Quickshell
import qs.components
import qs.services
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io


ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: 25

        Process {
            id: usernameProc
            command: ["whoami"]
            running: true
            stdout: SplitParser {
                onRead: data => usernameText.text = data
            }
        }

        Process {
            id: kernelProc
            command: ["bash", "-c", "uname -r | cut -d'-' -f1"]
            running: true
            stdout: SplitParser {
                onRead: data => kernelText.text = "󰣇 " + data
            }
        }

        Process {
            id: pkgProc
            command: ["bash", "-c", "pacman -Q | wc -l"]
            running: true
            stdout: SplitParser {
                onRead: data => pkgText.text = data + " "
            }
        }

    spacing: 50

    // Avatar
    Rectangle {
        id: faceRect
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 160
        radius: 10
        color: "#1a1a2e"
        property bool hovered: false
        
        
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: 160
                height: 160
                radius: 22
            }
        }

        Image {
            anchors.fill: parent
            source: Quickshell.env("HOME") + "/.face"
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            sourceSize.width: 160
            sourceSize.height: 160
            antialiasing: true
        }
        MouseArea {
            id: faceMouseArea
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
        }
    }

    Rectangle {
        id:usernameRect
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 50
        radius: 10
        gradient: ButtonGradient {
            hovered: usernameMouseArea.containsMouse
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 0.8
            anchors.topMargin: 1.5
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.1)
        }
        Text {
            id: usernameText
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: ""
            color: Colors.foreground
            font.bold: true
            font.pixelSize: 24
        }

        Behavior on scale {
            NumberAnimation {
                duration: Properties.duration
                easing.type: Easing.OutCubic
            } 
        }
        MouseArea {
            id: usernameMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: usernameRect.scale = 1.1
            onExited: usernameRect.scale = 1.0
        }

        
        
    }
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: -10

            RowLayout {
                Rectangle {
                    id: kernelRect
                    width: 90
                    height: 50
                    radius: 10
                    clip: false  // turn off clip, use layer instead
                    gradient: ButtonGradient {
                        hovered: kernelMouseArea.containsMouse
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 0.8
                        anchors.topMargin: 1.5
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        id: kernelText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: ""
                        color: Colors.foreground
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Properties.duration
                            easing.type: Easing.OutCubic
                        } 
                    }
                    MouseArea {
                        id: kernelMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: kernelRect.scale = 1.1
                        onExited: kernelRect.scale = 1.0
                    }
                }

                Rectangle {
                    id: pkgRect
                    width: 90; height: 50; radius: 10
                    gradient: ButtonGradient {
                        hovered: pkgMouseArea.containsMouse
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 0.8
                        anchors.topMargin: 1.5
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.1)
                    }
                    Text {
                        id: pkgText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: ""; color: Colors.foreground; font.pixelSize: 18; font.bold: true
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Properties.duration
                            easing.type: Easing.OutCubic
                        } 
                    }
                    MouseArea {
                        id: pkgMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: pkgRect.scale = 1.1
                        onExited: pkgRect.scale = 1.0
                    }
                }
            }

        RowLayout {
            Rectangle {
                id: custom1Rect
                width: 90
                height: 50
                radius: 10
                gradient: ButtonGradient {
                    hovered: custom1MouseArea.containsMouse
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 0.8
                    anchors.topMargin: 1.5
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.1)
                }
                Text {
                    id: custom1Text
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "RDP "
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Properties.duration
                        easing.type: Easing.OutCubic
                    } 
                }
                MouseArea {
                    id: custom1MouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: custom1Rect.scale = 1.1
                    onExited: custom1Rect.scale = 1.0
                    onClicked: Quickshell.execDetached(["bash", "-lc", "~/.config/custom/scripts/rdp-home.sh"])
                }
            }
            
            Rectangle {
                id: custom2Rect
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                radius: 10
                // clip: false  // turn off clip, use layer instead
                gradient: ButtonGradient {
                    hovered: custom2MouseArea.containsMouse
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 0.8
                    anchors.topMargin: 1.5
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.1)
                }
                Text {
                    id: custom2Text
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "RDP "
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Properties.duration
                        easing.type: Easing.OutCubic
                    } 
                }
                MouseArea {
                    id: custom2MouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: custom2Rect.scale = 1.1
                    onExited: custom2Rect.scale = 1.0
                    onClicked: Quickshell.execDetached(["bash", "-lc", "~/.config/custom/scripts/rdp-work.sh"])
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}