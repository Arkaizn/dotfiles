import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."

// VPN tab of the Network page (services/Vpn.qml): Tailscale, NetBird and
// NetworkManager VPN / WireGuard profiles, each with its state and a switch.
ColumnLayout {
    id: sec
    spacing: 14

    signal openProfiles()       // "import one" → the Profiles tab

    // read the VPNs only while this tab shows
    property bool watching: false
    function watch(on) { if (on === watching) return; watching = on; Vpn.watchers += on ? 1 : -1 }
    onVisibleChanged: watch(visible)
    Component.onCompleted: watch(visible)
    Component.onDestruction: watch(false)

    function stateText(v) {
        if (!v.installed) return ""
        if (v.on) return "Connected"
        if (v.needsLogin || v.state === "NeedsLogin") return "Needs login"
        return { Stopped: "Off", Idle: "Off", Starting: "Starting…", Connecting: "Connecting…" }[v.state] ?? v.state
    }

    Text {
        visible: Vpn.message !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "󰀦 " + Vpn.message
        color: Colors.red
        font.pixelSize: 12
    }

    NetCard {
        Layout.fillWidth: true
        visible: Vpn.tailscale.installed
        title: "Tailscale"
        icon: "󰖂"
        NetRow {
            first: true
            label: sec.stateText(Vpn.tailscale)
            desc: Vpn.tailscale.error || [Vpn.tailscale.tailnet, Vpn.tailscale.ip, Vpn.tailscale.peers].filter(x => x).join("  ·  ")
            ToggleSwitch {
                checked: Vpn.tailscale.on
                enabled: Vpn.busy === "" && Vpn.tailscale.state !== "NeedsLogin" && Vpn.tailscale.state !== "not running"
                onToggled: v => Vpn.setTailscale(v)
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: Vpn.netbird.installed
        title: "NetBird"
        icon: "󰒄"
        NetRow {
            first: true
            label: Vpn.busy === "netbird" ? (Vpn.netbird.needsLogin ? "Waiting for the login in the browser…" : "Switching…") : sec.stateText(Vpn.netbird)
            desc: Vpn.netbird.error || [Vpn.netbird.ip, Vpn.netbird.peers].filter(x => x).join("  ·  ")
            ActionButton {
                visible: Vpn.netbird.needsLogin === true
                icon: "󰍂"
                text: "Log in"
                interactive: Vpn.busy === ""
                onClicked: Vpn.setNetbird(true)
            }
            ToggleSwitch {
                visible: Vpn.netbird.needsLogin !== true
                checked: Vpn.netbird.on
                enabled: Vpn.busy === ""
                onToggled: v => Vpn.setNetbird(v)
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "VPN and WireGuard profiles"
        icon: "󰌾"
        NetRow {
            first: true
            visible: Vpn.profiles.length === 0
            label: "None yet"
            desc: "Import an OpenVPN or WireGuard file under Profiles"
            ActionButton { icon: "󰋺"; text: "Profiles"; onClicked: sec.openProfiles() }
        }
        Repeater {
            model: Vpn.profiles
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.name
                desc: (modelData.type === "wireguard" ? "WireGuard" : "VPN") + (Vpn.busy === modelData.uuid ? "  ·  switching…" : modelData.active ? "  ·  connected" : "")
                ToggleSwitch {
                    checked: modelData.active
                    enabled: Vpn.busy === ""
                    onToggled: v => Vpn.setProfile(modelData.uuid, v)
                }
            }
        }
    }
}
