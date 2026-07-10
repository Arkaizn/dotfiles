import Quickshell
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


    BackgroundEffect.blurRegion: Region {
        item: animatedRectangle
        radius: 24
    }


    Rectangle {
        id: animatedRectangle
        anchors.fill: parent
        color: "transparent"
        radius: 12  // Rounded corners

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16

            TextField {
                id: searchInput

                Layout.fillWidth: true
                placeholderText: "Type to search apps..."
                font.pixelSize: 18
                color: '#ffffff'
                focus: true  // Auto-focus when window opens

                background: Rectangle {
                    color: '#8d000000'
                    radius: 8
                }

                // For now, nothing happens on typing (as requested)
                // You can monitor changes here later
                onTextChanged: {
                    // console.log("Search text:", text)  // Uncomment to debug
                }
            }
        }
    }
}