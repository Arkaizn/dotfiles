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
    id: profileRoot
    anchors.fill: parent
    anchors.topMargin: 25

        // display name from the settings app (Profile), else the user name
        property string whoami: ""
        Process {
            id: usernameProc
            command: ["whoami"]
            running: true
            stdout: SplitParser {
                onRead: data => whoami = data
            }
        }

        Process {
            id: kernelProc
            command: ["bash", "-c", "uname -r | cut -d'-' -f1"]
            running: true
            stdout: SplitParser {
                onRead: data => kernelRect.iconText = "󰣇 " + data
            }
        }

        Process {
            id: pkgProc
            command: ["bash", "-c", "pacman -Q | wc -l"]
            running: true
            stdout: SplitParser {
                onRead: data => pkgRect.iconText = data + " "
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
            // ?r= changes with a new picture from the settings app (no stale cache)
            source: "file://" + Quickshell.env("HOME") + "/.face?r=" + (Settings.profile.faceRev ?? 0)
            cache: false
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

    Item {
        id:username
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 50

        ButtonBackground {
            id: usernameRect
            hovered: root.hovered
            iconText: Settings.profile.name || profileRoot.whoami
            iconSize: 24
            fontBold: true
        }
        MouseArea {
            id: usernameMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: usernameRect.scale = 1.1
            onExited: usernameRect.scale = 1.0
            onPressed: usernameRect.scale = Properties.onPressedButtonScale
            onReleased: usernameRect.scale = containsMouse ? 1.1 : 1.0
            onCanceled: usernameRect.scale = 1.0
        }

        
        
    }
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: -10

            RowLayout {
                Item {
                    width: 90
                    height: 50
                    clip: false  // turn off clip, use layer instead
                    ButtonBackground {
                        id: kernelRect
                        hovered: root.hovered
                        iconText: ""
                        iconSize: Properties.iconSize
                        fontBold: true
                    }
                    MouseArea {
                        id: kernelMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: kernelRect.scale = 1.1
                        onExited: kernelRect.scale = 1.0
                        onPressed: kernelRect.scale = Properties.onPressedButtonScale
                        onReleased: kernelRect.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: kernelRect.scale = 1.0
                    }
                }

                Item {
                    width: 90
                    height: 50
                    clip: false  // turn off clip, use layer instead
                    ButtonBackground {
                        id: pkgRect
                        hovered: root.hovered
                        iconText: ""
                        iconSize: Properties.iconSize
                        fontBold: true
                    }
                    MouseArea {
                        id: pkgMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: pkgRect.scale = 1.1
                        onExited: pkgRect.scale = 1.0
                        onPressed: pkgRect.scale = Properties.onPressedButtonScale
                        onReleased: pkgRect.scale = containsMouse ? 1.1 : 1.0
                        onCanceled: pkgRect.scale = 1.0
                    }
                }
            }

        RowLayout {
            Item {
                width: 90
                height: 50
                ButtonBackground {
                        id: custom1Rect
                        hovered: root.hovered
                        iconText: "RDP "
                        iconSize: Properties.iconSize
                        fontBold: true
                }
                MouseArea {
                    id: custom1MouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: custom1Rect.scale = 1.1
                    onExited: custom1Rect.scale = 1.0
                    onPressed: custom1Rect.scale = Properties.onPressedButtonScale
                    onReleased: custom1Rect.scale = containsMouse ? 1.1 : 1.0
                    onCanceled: custom1Rect.scale = 1.0
                    onClicked: Quickshell.execDetached(["bash", "-lc", "~/.config/custom/scripts/rdp-home.sh"])
                }
            }
            
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                ButtonBackground {
                        id: custom2Rect
                        hovered: root.hovered
                        iconText: "RDP "
                        iconSize: Properties.iconSize
                        fontBold: true
                }
                MouseArea {
                    id: custom2MouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: custom2Rect.scale = 1.1
                    onExited: custom2Rect.scale = 1.0
                    onPressed: custom2Rect.scale = Properties.onPressedButtonScale
                    onReleased: custom2Rect.scale = containsMouse ? 1.1 : 1.0
                    onCanceled: custom2Rect.scale = 1.0
                    onClicked: Quickshell.execDetached(["bash", "-lc", "~/.config/custom/scripts/rdp-work.sh"])
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}