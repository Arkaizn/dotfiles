import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Effects

PanelWindow {
    id: testing
    visible: false
    anchors {
        top: true
        right: true
    }
    implicitWidth: 400
    implicitHeight: 400
    color: '#00000000'
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property int duration: 500

    property bool panelOpen: false

    IpcHandler {
        target: "testing"
        function toggle(): void {
            if (testing.visible) {
                testing.panelOpen = false
                closeTimer.restart()
            } else {
                closeTimer.stop()
                testing.visible = true
                testing.panelOpen = true
            }
        }
    }

    BackgroundEffect.blurRegion: Region {
        item: animatedRectangle
        radius: 24
    }

    Timer {
        id: closeTimer
        interval: testing.duration
        repeat: false
        onTriggered: testing.visible = false
    }

    Rectangle {
        id: animatedRectangle
        anchors { 
            right: parent.right
            rightMargin: 10
        }
        width: 200
        height: 400
        color: "transparent"
        radius: 12

        // slides between hidden (-400) and shown (400 - height) based on panelOpen
        y: testing.panelOpen ? (0) : -animatedRectangle.height

        Behavior on y {
            NumberAnimation {
                duration: testing.duration
                easing.type: Easing.InOutQuad
            }
        }
    }
}