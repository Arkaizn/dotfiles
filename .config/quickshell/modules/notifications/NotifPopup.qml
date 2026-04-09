import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

PanelWindow {
    id: root
    visible: false
    anchors { 
        top: true
        right: true 
        }
    implicitWidth: 360
    implicitHeight: row.implicitHeight + 2 * row.anchors.margins
    color: "transparent"

    property string title: ""
    property string body: ""
    property string appName: ""
    property string appIcon: ""

    function notify(summary, body, appName, appIcon) {
        root.title = summary
        root.body = body
        root.appName = appName
        root.appIcon = appIcon
        root.visible = true
        timer.restart()
    }

    Timer {
        id: timer
        interval: 3000
        onTriggered: root.visible = false
    }

    Rectangle {
        anchors { 
            fill: parent
            rightMargin: 10 
            }
        radius: 10
        color: "#27000000"
        
        Row {
            id:row
            anchors { 
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
                }
            spacing: 6

            Image {
                id: appIconImg
                visible: root.appIcon !== "" && root.appIcon !== null
                width: 70; height: width
                source: Quickshell.iconPath(root.appIcon, true)
            }

            ColumnLayout {
                id: col
                spacing: 6
                
                Text {
                    text: root.appName
                    font { 
                        bold: true
                        pixelSize: 12
                        }
                    color: Colors.color4
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.title
                    font { 
                        bold: true
                        pixelSize: 16
                        }
                    color: "#cdffffff"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.body
                    color: "#acffffff"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}