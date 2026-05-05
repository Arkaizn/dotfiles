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
    anchors.margins: 20

        Process {
            id: usernameProc
            command: ["whoami"]
            running: true
            stdout: SplitParser {
                onRead: data => username.text = data
            }
        }

        Process {
            id: kernelProc
            command: ["bash", "-c", "uname -r | cut -d'-' -f1"]
            running: true
            stdout: SplitParser {
                onRead: data => kernelText.text = data
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
    // anchors.horizontalCenter: parent.horizontalCenter

    spacing: 50

    // Avatar — rounded square, matching the widget card style
    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 160
        radius: 10
        color: "#1a1a2e"
        clip: false  // turn off clip, use layer instead
        property bool hovered: false
        
        
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: 110
                height: 110
                radius: 10
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
    }
    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 160
        height: 50
        radius: 10
        // color: "#1a1a2e"
        gradient: Gradient {
            GradientStop { position: 0.0;color: Qt.rgba(0.5, 0.5, 0.5, 0.85) }
            GradientStop { position: 1.0 ;color: Qt.rgba(0.2, 0.2, 0.2, 0.6) }
        }

        Text {
            id: username
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: ""
            color: Colors.foreground
            font.bold: true
            font.pixelSize: 24
        }
    }
    ColumnLayout  {
        RowLayout {
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                radius: 10
                clip: false  // turn off clip, use layer instead
                gradient: Gradient {
                    GradientStop { position: 0.0;color: Qt.rgba(0.5, 0.5, 0.5, 0.85) }
                    GradientStop { position: 1.0 ;color: Qt.rgba(0.2, 0.2, 0.2, 0.6) }
                }

                Text {
                    id: kernelText
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
            }
            
        Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                radius: 10
                clip: false  // turn off clip, use layer instead
                gradient: Gradient {
                    GradientStop { position: 0.0;color: Qt.rgba(0.5, 0.5, 0.5, 0.85) }
                    GradientStop { position: 1.0 ;color: Qt.rgba(0.2, 0.2, 0.2, 0.6) }
                }
                
                // Layout.alignment: Qt.AlignHCenter
                Text {
                    id: pkgText
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Item { Layout.fillHeight: true }
        }
        RowLayout {
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                radius: 10
                clip: false  // turn off clip, use layer instead
                gradient: Gradient {
                    GradientStop { position: 0.0;color: Qt.rgba(0.5, 0.5, 0.5, 0.85) }
                    GradientStop { position: 1.0 ;color: Qt.rgba(0.2, 0.2, 0.2, 0.6) }
                }

                Text {
                    id: kernelText2
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
            }
            
        Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 90
                height: 50
                radius: 10
                clip: false  // turn off clip, use layer instead
                gradient: Gradient {
                    GradientStop { position: 0.0;color: Qt.rgba(0.5, 0.5, 0.5, 0.85) }
                    GradientStop { position: 1.0 ;color: Qt.rgba(0.2, 0.2, 0.2, 0.6) }
                }
                
                // Layout.alignment: Qt.AlignHCenter
                Text {
                    id: pkgText2
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                    color: Colors.foreground
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}