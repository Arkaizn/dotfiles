import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Connections page: saved SSH / RDP / VNC connections (services/RemoteConnections.qml),
// opened from the launcher's connections tab.
ColumnLayout {
    id: page
    spacing: 16

    property string editing: ""            // connection id, "new" or ""
    property bool importing: false
    property string confirmDelete: ""
    property var have: ({})

    Component.onCompleted: {
        Jobs.which(["ssh", "xfreerdp3", "vncviewer", "kitty", "nc", "secret-tool", "zenity"], h => page.have = h)
        RemoteConnections.probe()
    }

    readonly property var missing: Object.keys(have).filter(b => !have[b])

    NetCard {
        Layout.fillWidth: true
        visible: page.missing.length > 0
        title: "Missing programs"
        icon: "󰀦"
        NetRow {
            first: true
            label: page.missing.join(", ")
            desc: page.missing.map(b => Jobs.installHint(b)).join("   ·   ")
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Saved connections"
        header: [
            ActionButton { icon: "󰋺"; text: "Import"; onClicked: { page.importing = true; page.editing = "" } },
            ActionButton { icon: "󰐕"; text: "New"; primary: true; onClicked: { page.editing = "new"; page.importing = false } }
        ]

        Reveal {
            open: page.editing === "new"
            Loader {
                Layout.fillWidth: true
                active: page.editing === "new"
                sourceComponent: ConnectionEditor { onDone: page.editing = "" }
            }
        }

        NetRow {
            first: true
            visible: RemoteConnections.list.length === 0 && page.editing !== "new"
            label: "No connections yet"
            desc: "Add one, or import your RDP / VNC scripts and ~/.ssh/config hosts. Open them from the launcher's 󰢹 tab."
        }

        Repeater {
            model: RemoteConnections.list
            ColumnLayout {
                id: entry
                required property var modelData
                required property int index
                readonly property var c: modelData
                readonly property string reach: RemoteConnections.reach[c.id] ?? ""
                Layout.fillWidth: true
                spacing: 0

                NetRow {
                    first: entry.index === 0 && page.editing !== "new"
                    label: RemoteConnections.types[entry.c.type].icon + "  " + entry.c.name
                    desc: RemoteConnections.types[entry.c.type].name + "  ·  " + (entry.c.user ? entry.c.user + "@" : "") + entry.c.host + ":" + entry.c.port
                          + (entry.c.password === "keyring" ? "  ·  password in keyring" : entry.c.password === "ask" ? "  ·  asks for the password" : "")
                          + (entry.reach === "up" ? "  ·  reachable" : entry.reach === "down" ? "  ·  not reachable" : "")
                    RowLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: 8; implicitHeight: 8; radius: 4
                            visible: entry.reach !== ""
                            color: entry.reach === "up" ? Colors.green : entry.reach === "down" ? Colors.red : Colors.fade(0.3)
                        }
                        IconButton { icon: "󰐊"; tooltip: "Connect"; onClicked: RemoteConnections.connect(entry.c.id) }
                        IconButton {
                            icon: "󰏫"; tooltip: "Edit"
                            active: page.editing === entry.c.id
                            onClicked: page.editing = page.editing === entry.c.id ? "" : entry.c.id
                        }
                        IconButton {
                            icon: page.confirmDelete === entry.c.id ? "󰄬" : "󰆴"
                            tooltip: page.confirmDelete === entry.c.id ? "Click again to delete" : "Delete (and its keyring password)"
                            textColor: page.confirmDelete === entry.c.id ? Colors.red : Properties.color
                            onClicked: {
                                if (page.confirmDelete === entry.c.id) { RemoteConnections.remove(entry.c.id); page.confirmDelete = "" }
                                else { page.confirmDelete = entry.c.id; confirmTimer.restart() }
                            }
                        }
                    }
                }
                Reveal {
                    open: page.editing === entry.c.id
                    Loader {
                        Layout.fillWidth: true
                        active: page.editing === entry.c.id
                        sourceComponent: ConnectionEditor { conn: entry.c; onDone: page.editing = "" }
                    }
                }
            }
        }
    }
    Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirmDelete = "" }

    NetCard {
        Layout.fillWidth: true
        visible: page.importing
        title: "Import"
        Loader {
            Layout.fillWidth: true
            active: page.importing
            sourceComponent: ConnectionImport { onDone: page.importing = false }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "How passwords are kept"
        NetRow {
            first: true
            wide: true
            label: "Never in the settings file"
            desc: "RDP: in your keyring (secret-tool), or a prompt every time; handed to xfreerdp3 in an environment variable only you can read, not on the command line. SSH: your keys / agent, or ssh asks in the terminal. VNC: vncviewer asks."
        }
    }
}
