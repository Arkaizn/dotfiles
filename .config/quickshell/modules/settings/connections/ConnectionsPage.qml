import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Connections page: saved SSH / RDP / VNC connections (services/RemoteConnections.qml),
// opened from the launcher's connections tab; and this device's own VNC
// server (services/VncServer.qml) with its firewall rule.
ColumnLayout {
    id: page
    spacing: 16

    property string editing: ""            // connection id, "new" or ""
    property bool importing: false
    ConfirmArm { id: deleteArm }
    readonly property alias confirmDelete: deleteArm.armed     // the connection waiting for its second click
    property var have: ({})

    property string firewall: ""            // ufw: "active" / "inactive" / "" (not installed)
    Component.onCompleted: {
        Jobs.which(["ssh", "xfreerdp3", "vncviewer", "kitty", "nc", "secret-tool", "zenity"], h => page.have = h)
        RemoteConnections.probe()
        VncServer.refresh()
        Jobs.run(["sh", "-c", "command -v ufw >/dev/null && systemctl is-active ufw"], (c, out) => page.firewall = out.trim())
    }
    // a terminal for root actions (firewall); fixed script, values passed as data
    function terminal(title, script, args) {
        Quickshell.execDetached(["kitty", "--title", title, "bash", "-c",
            script + '\necho; read -r -p "Done. Press Enter to close." _', "bash"].concat(args ?? []))
    }
    // a change to a running server applies by restarting it
    function setServer(k, v) { VncServer.setOpt(k, v); if (VncServer.running) VncServer.restart() }

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
                                if (deleteArm.confirm(entry.c.id)) RemoteConnections.remove(entry.c.id)
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

    NetCard {
        Layout.fillWidth: true
        title: "This device (VNC server)"
        icon: "󰢹"
        NetRow {
            first: true
            label: VncServer.starting ? "Starting…"
                 : VncServer.running ? "On  ·  " + (VncServer.lanAddress || "all addresses") + ":" + VncServer.port
                 : "Off"
            desc: VncServer.error !== "" ? "󰀦 " + VncServer.error
                : "Lets another computer see" + (VncServer.viewOnly ? "" : " and control") + " this screen (wayvnc). Login: your user name and password, over an encrypted connection (RSA-AES)."
            ToggleSwitch {
                checked: VncServer.running || VncServer.starting
                onToggled: v => v ? VncServer.start() : VncServer.stop()
            }
        }
        NetRow {
            sub: true
            visible: VncServer.running
            label: "Connect from another computer"
            desc: "vncviewer " + (VncServer.lanAddress || "<this device>") + "::" + VncServer.port
                  + "  ·  needs a viewer with RSA-AES (TigerVNC 1.13+, RealVNC). You get a notification when someone connects."
        }
        Repeater {
            model: VncServer.clients
            NetRow {
                required property var modelData
                sub: true
                label: "󰀄  " + (modelData.username || "connected") + (modelData.address ? "  ·  " + modelData.address : "")
                ActionButton { icon: "󰅖"; text: "Disconnect"; onClicked: VncServer.disconnect(modelData.id) }
            }
        }
        NetRow {
            label: "Monitor"
            desc: "the one it shows (one at a time)"
            DropdownControl {
                implicitWidth: 200
                options: [{ label: "Focused when started", value: "" }].concat(Quickshell.screens.map(s => ({ label: s.name, value: s.name, hint: s.width + "×" + s.height })))
                value: VncServer.output
                onEdited: v => page.setServer("output", v)
            }
        }
        NetRow {
            label: "View only"
            desc: "the other side sees the screen but can't use mouse or keyboard"
            ToggleSwitch { checked: VncServer.viewOnly; onToggled: v => page.setServer("viewOnly", v) }
        }
        NetRow {
            label: "Port"
            NumberControl { from: 1024; to: 65535; value: VncServer.port; onEdited: v => page.setServer("port", Math.round(v)) }
        }
        NetRow {
            label: "Start with the shell"
            desc: "turns it on at login (only while you're logged in: it shares your session)"
            ToggleSwitch { checked: VncServer.autostart; onToggled: v => VncServer.setOpt("autostart", v) }
        }
        NetRow {
            label: "Firewall"
            desc: page.firewall === "active"
                  ? "ufw is on: the port has to be allowed. Your network only (" + (VncServer.lanNet || "LAN") + ") is safest; never open it to the internet."
                  : page.firewall === "inactive" ? "ufw is installed but off: nothing blocks the port"
                  : "no ufw: nothing here blocks the port"
            RowLayout {
                spacing: 6
                visible: page.firewall !== ""
                ActionButton {
                    icon: "󰒃"
                    text: "Allow from my network"
                    interactive: VncServer.lanNet !== ""
                    onClicked: page.terminal("Firewall: allow VNC", 'sudo ufw allow from "$1" to any port "$2" proto tcp comment "VNC (quickshell)" && sudo ufw status',
                                             [VncServer.lanNet, String(VncServer.port)])
                }
                ActionButton {
                    icon: "󰅖"
                    text: "Remove rule"
                    onClicked: page.terminal("Firewall: remove VNC rule", 'sudo ufw delete allow from "$1" to any port "$2" proto tcp; sudo ufw status',
                                             [VncServer.lanNet, String(VncServer.port)])
                }
            }
        }
    }

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
