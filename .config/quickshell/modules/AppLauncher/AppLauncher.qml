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
    id: appLauncher
    visible: false
    anchors {
        bottom: true   
        // right: true     
    }
    implicitWidth: 400
    implicitHeight: 400
    color: '#00000000'
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    IpcHandler {
        target: "appLauncher"
        function toggle(): void {
            appLauncher.visible = !appLauncher.visible
            if (appLauncher.visible) {
                searchField.text = ""
                searchField.forceActiveFocus()
                resultsList.currentIndex = 0
            }
        }
    }

    // Filtered + sorted list of apps, recomputed whenever the query changes
    property var filteredApps: {
        const all = [...DesktopEntries.applications.values]
            .filter(e => e.name)
            .sort((a, b) => a.name.localeCompare(b.name))

        const q = searchField.text.trim().toLowerCase()
        if (q === "") return all

        return all.filter(e => {
            const name = (e.name || "").toLowerCase()
            const comment = (e.comment || "").toLowerCase()
            const keywords = (e.keywords || []).join(" ").toLowerCase()
            return name.includes(q) || comment.includes(q) || keywords.includes(q)
        })
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        appLauncher.visible = false
        searchField.text = ""
    }

    BackgroundEffect.blurRegion: Region {
        item: animatedRectangle
        radius: 24
    }

    Rectangle {
        id: animatedRectangle
        anchors.fill: parent
        color: "transparent"
        radius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            
        TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Properties.buttonHeight
                    placeholderText: "Search"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                    color: Properties.color
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter

                    background: Rectangle {
                        radius: Properties.radius
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, searchField.activeFocus ? 0.28 : 0.18)
                        gradient: ButtonGradient { hovered: searchField.activeFocus }
                    }

                    Text {
                        id: clearIcon
                        text: "✕"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                        visible: searchField.text.length > 0
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchField.text = ""
                        }
                    }
                }

            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: filteredApps
                currentIndex: 0

                delegate: Rectangle {
                    width: resultsList.width
                    height: 44
                    radius: 6

                    color: ListView.isCurrentItem ? '#4dffffff' : 'transparent'

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {}
                        Text {
                            text: modelData.name
                            color: '#ffffff'
                            font.pixelSize: 16
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: appLauncher.launch(modelData)
                    }
                }
            }
        }
    }
}