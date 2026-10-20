import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."

// Wi-Fi tab of the Network page: the saved networks (auto-connect, priority,
// forget; password and the rest in the profile editor) and joining a hidden
// network (Network.joinHidden).
ColumnLayout {
    id: sec
    spacing: 14

    signal editProfile(string uuid)      // → the profile editor (password, …)

    // highest priority first, then the most recently used
    readonly property var saved: Network.connections.filter(c => c.type === "802-11-wireless")
        .sort((a, b) => (b.priority - a.priority) || (b.timestamp - a.timestamp))

    function lastUsed(ts) {
        if (!ts) return "never used"
        const days = Math.floor((Date.now() / 1000 - ts) / 86400)
        return days < 1 ? "used today" : days === 1 ? "used yesterday" : days < 60 ? "used " + days + " days ago" : "last used " + Format.day(ts * 1000)
    }

    function setPriority(c, n) {
        Network.modify(c.uuid, { "connection.autoconnect-priority": n }, "", ok => { if (!ok) Network.say("Could not change the priority", true) })
    }

    ConfirmArm { id: arm }

    NetCard {
        Layout.fillWidth: true
        title: "Saved networks"
        icon: "󰖩"
        NetRow {
            first: true
            visible: sec.saved.length === 0
            label: "None yet"
            desc: "Networks you connect to are saved here"
        }
        Repeater {
            model: sec.saved
            NetRow {
                id: srow
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.name
                desc: [modelData.active ? "connected" : sec.lastUsed(modelData.timestamp),
                       modelData.autoconnect ? "priority " + modelData.priority : ""].filter(x => x).join("  ·  ")
                IconButton {
                    visible: srow.modelData.autoconnect
                    icon: "󰁝"
                    tooltip: "Higher priority"
                    interactive: !Network.busy
                    onClicked: sec.setPriority(srow.modelData, srow.modelData.priority + 1)
                }
                IconButton {
                    visible: srow.modelData.autoconnect
                    icon: "󰁅"
                    tooltip: "Lower priority"
                    interactive: !Network.busy
                    onClicked: sec.setPriority(srow.modelData, srow.modelData.priority - 1)
                }
                ToggleSwitch {
                    checked: srow.modelData.autoconnect
                    enabled: !Network.busy
                    onToggled: v => Network.modify(srow.modelData.uuid, { "connection.autoconnect": v ? "yes" : "no" }, "",
                                                   ok => { if (!ok) Network.say("Could not change auto-connect", true) })
                }
                IconButton {
                    icon: "󰏫"
                    tooltip: "Password and more"
                    onClicked: sec.editProfile(srow.modelData.uuid)
                }
                IconButton {
                    icon: "󰆴"
                    tooltip: arm.armed === srow.modelData.uuid ? "Click again to forget" : "Forget"
                    active: arm.armed === srow.modelData.uuid
                    interactive: !Network.busy
                    onClicked: if (arm.confirm(srow.modelData.uuid)) Network.remove(srow.modelData.uuid, srow.modelData.name)
                }
            }
        }
        NetRow {
            visible: sec.saved.length > 1
            label: "Order"
            desc: "With auto-connect on, the network with the highest priority in range is joined first"
        }
    }

    NetCard {
        id: hidden
        Layout.fillWidth: true
        title: "Join a hidden network"
        icon: "󰖪"

        property string ssid: ""
        property string security: "wpa-psk"
        property string password: ""
        property bool joining: false
        readonly property string problem: ssid.trim() === "" ? "Enter the network name"
            : security !== "open" && password.length < 8 ? "The password has at least 8 characters" : ""

        NetRow {
            first: true
            label: "Network name (SSID)"
            SearchField {
                implicitWidth: 240
                implicitHeight: Properties.buttonHeight
                icon: ""
                text: hidden.ssid
                onTextEdited: hidden.ssid = text
            }
        }
        NetRow {
            label: "Security"
            DropdownControl {
                implicitWidth: 240
                options: [{ label: "WPA / WPA2 Personal", value: "wpa-psk" }, { label: "WPA3 Personal", value: "sae" }, { label: "None (open)", value: "open" }]
                value: hidden.security
                onEdited: v => hidden.security = v
            }
        }
        NetRow {
            visible: hidden.security !== "open"
            label: "Password"
            SearchField {
                id: pw
                implicitWidth: 240
                implicitHeight: Properties.buttonHeight
                icon: "󰌾"
                password: !showPw.active
                text: hidden.password
                onTextEdited: hidden.password = text
            }
            IconButton {
                id: showPw
                icon: active ? "󰈈" : "󰈉"
                tooltip: "Show password"
                onClicked: active = !active
            }
        }
        NetRow {
            Text {
                text: Network.busy && hidden.joining ? "Connecting…" : hidden.problem
                color: Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
            ActionButton {
                icon: "󰖩"
                text: "Join"
                primary: true
                interactive: hidden.problem === "" && !Network.busy
                onClicked: {
                    hidden.joining = true
                    Network.joinHidden(hidden.ssid.trim(), hidden.security, hidden.password, ok => {
                        hidden.joining = false
                        if (ok) { hidden.ssid = ""; hidden.password = "" }
                    })
                }
            }
        }
    }
}
