import QtQuick
import Quickshell.Widgets
import Quickshell
import qs.components
import qs.services
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects


ColumnLayout {
    id: profileRoot
    anchors.fill: parent
    anchors.topMargin: 25

        // display name from the settings app (Profile), else the user name
        property string whoami: ""
        // asked once when the card is created (argv only, the pipes are done here)
        Component.onCompleted: {
            Jobs.run(["whoami"], (c, out) => whoami = (out ?? "").trim())
            Jobs.run(["uname", "-r"], (c, out) => kernelRect.iconText = "󰣇 " + (out ?? "").trim().split("-")[0])
            Jobs.run(["pacman", "-Q"], (c, out) => pkgRect.iconText = (out ?? "").split("\n").filter(l => l !== "").length + " ")
        }

    spacing: 50

    // Avatar — rounded by clipping (was an OpacityMask layer: an extra
    // offscreen texture just for the corners)
    ClippingRectangle {
        id: faceRect
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 160
        radius: 22          // the hero avatar's own corner (DESIGN.md → Exceptions: dashboard)
        color: Colors.surfaceWell
        property bool hovered: false

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
            hovered: usernameMouseArea.containsMouse
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
                        hovered: kernelMouseArea.containsMouse
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
                        hovered: pkgMouseArea.containsMouse
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
                        hovered: custom1MouseArea.containsMouse
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
                        hovered: custom2MouseArea.containsMouse
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