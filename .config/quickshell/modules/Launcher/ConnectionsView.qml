import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

// Saved SSH / RDP / VNC connections (services/RemoteConnections.qml). Enter or a
// click connects. Reachability (a dot per row) is checked when the tab opens.
//
// Sibling of AppSearch.qml — same contract, so Launcher.qml can drive it the
// same way.
ColumnLayout {
    id: root

    property string query: ""
    property int maxHeight: 360
    property bool active: false

    signal closeRequested()

    spacing: 8

    onActiveChanged: if (active) RemoteConnections.probe()

    // recent first, then by name; the query matches name, host, user and type
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return RemoteConnections.list
            .filter(c => q === "" || [c.name, c.host, c.user, c.type].some(x => x.toLowerCase().includes(q)))
            .sort((a, b) => (b.lastUsed - a.lastUsed) || a.name.localeCompare(b.name))
    }
    onShownChanged: list.currentIndex = shown.length > 0 ? 0 : -1

    function moveDown() { list.incrementCurrentIndex() }
    function moveUp() { list.decrementCurrentIndex() }
    function activateCurrent() {
        const c = shown[list.currentIndex]
        if (!c) return
        RemoteConnections.connect(c.id)
        root.closeRequested()
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(root.shown.length, 1) * 52)
        clip: true
        model: root.shown
        highlightMoveDuration: 80
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property var c: modelData
            readonly property bool isCurrent: list.currentIndex === index
            readonly property string reach: RemoteConnections.reach[c.id] ?? ""
            width: list.width
            height: 52

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    RemoteConnections.connect(cell.c.id)
                    root.closeRequested()
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 6
                color: cell.isCurrent ? Colors.fade(0.13) : hover.hovered ? Colors.fade(0.08) : "transparent"
                border.color: cell.isCurrent ? Colors.fade(0.22) : "transparent"
                border.width: 0.5
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Text {
                    text: RemoteConnections.types[cell.c.type].icon
                    color: Colors.color6
                    font.pixelSize: 20
                    font.family: Properties.fontFamily
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: cell.c.name
                        color: cell.isCurrent ? Colors.ink : Colors.fade(0.85)
                        font.pixelSize: 14
                        font.weight: cell.isCurrent ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (cell.c.user ? cell.c.user + "@" : "") + cell.c.host
                              + (cell.c.port !== RemoteConnections.types[cell.c.type].port ? ":" + cell.c.port : "")
                        color: Colors.fade(0.45)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                }
                Text {
                    text: RemoteConnections.types[cell.c.type].name + (cell.c.password === "keyring" ? "  󰌋" : cell.c.password === "ask" ? "  󰌾" : "")
                    color: Colors.fade(0.4)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                // reachable? (port open)
                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    visible: cell.reach !== ""
                    color: cell.reach === "up" ? Colors.green : cell.reach === "down" ? Colors.red : Colors.fade(0.3)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.shown.length === 0
            text: RemoteConnections.list.length === 0 ? "No saved connections: add or import them in Settings → Connections"
                                                : "No matching connections"
            color: Colors.fade(0.35)
            font.pixelSize: 13
        }
    }
}
