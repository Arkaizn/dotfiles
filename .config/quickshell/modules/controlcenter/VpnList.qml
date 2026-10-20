import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// VPN list under the control center's VPN tile (services/Vpn.qml): a switch
// per VPN, NetBird's "Log in" when its login expired, and the settings page.
ColumnLayout {
    id: root

    property bool active: false    // read the VPNs only while the list is shown
    property bool watching: false
    onActiveChanged: { if (active !== watching) { Vpn.watchers += active ? 1 : -1; watching = active } }
    Component.onDestruction: if (watching) Vpn.watchers -= 1

    spacing: 6

    // { key, name, on, detail, login }
    readonly property var rows: [
        Vpn.tailscale.installed ? { key: "tailscale", name: "Tailscale", on: Vpn.tailscale.on, login: false,
                                    detail: Vpn.tailscale.on ? Vpn.tailscale.ip : (Vpn.tailscale.state === "NeedsLogin" ? "needs login" : "off") } : null,
        Vpn.netbird.installed ? { key: "netbird", name: "NetBird", on: Vpn.netbird.on, login: Vpn.netbird.needsLogin === true,
                                  detail: Vpn.netbird.on ? Vpn.netbird.ip : Vpn.netbird.needsLogin === true ? "login expired" : "off" } : null
    ].filter(r => r !== null).concat(Vpn.profiles.map(p => ({ key: p.uuid, name: p.name, on: p.active, login: false,
                                                              detail: (p.type === "wireguard" ? "WireGuard" : "VPN") + (p.active ? "" : " · off") })))

    function toggle(r) {
        if (r.key === "tailscale") Vpn.setTailscale(!r.on)
        else if (r.key === "netbird") Vpn.setNetbird(!r.on)
        else Vpn.setProfile(r.key, !r.on)
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Vpn.message !== "" ? Vpn.message : root.rows.length === 0 ? "No VPN found" : Vpn.upNames.length + " of " + root.rows.length + " connected"
            color: Vpn.message !== "" ? Colors.red : Colors.fade(0.55)
            elide: Text.ElideRight
            font.pixelSize: 11
        }
        IconButton {
            implicitWidth: 26; implicitHeight: 26
            iconSize: 12
            icon: "󰒓"
            tooltip: "VPN settings"
            onClicked: { Panels.close("controlCenter"); Panels.call("settings", "openPage", "vpn") }
        }
    }

    Repeater {
        model: root.rows
        Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 9
            color: mouse.containsMouse ? Colors.fade(0.08) : Colors.fade(0.04)
            readonly property bool busy: Vpn.busy === modelData.key
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: Vpn.busy === ""
                onClicked: root.toggle(row.modelData)
            }
            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8
                Text { text: "󰖂"; color: row.modelData.on ? Colors.color6 : Colors.fade(0.4); font.pixelSize: 14; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: row.modelData.name; color: Colors.ink; font.pixelSize: 12; elide: Text.ElideRight }
                Text {
                    text: row.busy ? (row.modelData.login ? "log in in the browser…" : "…") : row.modelData.login ? "Log in" : row.modelData.detail
                    color: row.modelData.login ? Colors.color6 : Colors.fade(0.55)
                    font.pixelSize: 11
                }
            }
        }
    }
}
