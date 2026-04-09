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
    implicitHeight: col.implicitHeight + 24
    color: "transparent"

    property string title: ""
    property string body: ""
    property string appname: ""

    function notify(summary, body, appName) {
        root.title = summary
        root.body = body
        root.appname = appName
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

        ColumnLayout {
            id: col
            anchors { 
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12 
                }
            spacing: 6
            
            Text {
                text: root.appname
                font { 
                    bold: true
                    pixelSize: 10
                    }
                color: Colors.color4
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.title
                font { 
                    bold: true
                    pixelSize: 14 
                    }
                color: "#cdffffff"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.body
                color: "#acffffff"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
}