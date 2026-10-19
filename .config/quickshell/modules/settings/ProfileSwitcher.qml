import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Bottom of the settings sidebar, like Zen's spaces: one icon per settings
// profile (services/SettingsProfiles.qml), the active one lit with a dot under
// it. Click one to switch to it; + / the gear opens the Profiles page.
Item {
    id: root
    signal manage()
    signal failed()                     // apply didn't work: the Profiles page shows why

    implicitHeight: Properties.buttonHeight + 10

    Component.onCompleted: SettingsProfiles.refresh()

    readonly property var list: SettingsProfiles.profiles.filter(p => !p.broken)

    // a thin line above, like a footer
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6 }
        height: 1
        color: Colors.fade(0.08)
    }

    Flickable {
        id: strip
        anchors { left: parent.left; right: manageBtn.left; rightMargin: 4; top: parent.top; topMargin: 6; bottom: parent.bottom }
        contentWidth: row.implicitWidth
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        RowLayout {
            id: row
            // centred while they fit
            x: Math.max(0, (strip.width - implicitWidth) / 2)
            height: strip.height
            spacing: 4

            Repeater {
                model: root.list
                Item {
                    id: slot
                    required property var modelData
                    readonly property bool current: modelData.name === SettingsProfiles.active
                    implicitWidth: Properties.buttonHeight
                    implicitHeight: parent.height

                    IconButton {
                        anchors.top: parent.top
                        icon: slot.modelData.icon || slot.modelData.name.charAt(0).toUpperCase()
                        active: slot.current
                        textColor: slot.current ? Colors.color6 : Properties.color
                        tooltip: slot.modelData.name + (slot.current ? " (active)" : "  ·  click to switch")
                        onClicked: if (!slot.current) SettingsProfiles.apply(slot.modelData.name, ok => { if (!ok) root.failed() })
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                        width: slot.current ? 12 : 4
                        height: 3
                        radius: 1.5
                        color: slot.current ? Colors.color6 : Colors.fade(0.25)
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Text {
                visible: root.list.length === 0
                text: "No profiles yet"
                color: Colors.fade(0.4)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }
        WheelHandler {
            orientation: Qt.Vertical
            onWheel: e => strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX - e.angleDelta.y / 2))
        }
    }

    IconButton {
        id: manageBtn
        anchors { right: parent.right; top: parent.top; topMargin: 6 }
        icon: root.list.length === 0 ? "󰐕" : "󰒓"
        tooltip: root.list.length === 0 ? "Save the current settings as a profile" : "Manage profiles"
        onClicked: root.manage()
    }
}
