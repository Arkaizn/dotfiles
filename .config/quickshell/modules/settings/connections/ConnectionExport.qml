import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Export saved connections to a JSON file (RemoteConnections.exportTo): all of
// them, or the ones picked here (the row's export button preselects just that
// one). Keyring passwords stay out of the file unless "Include passwords" is
// on — then they're in it as plain text.
ColumnLayout {
    id: exp
    signal done()

    property var preselect: []             // ids; empty = all
    property var picked: ({})              // id → bool
    property bool withPasswords: false
    property string message: ""
    property bool error: false

    Component.onCompleted: {
        const p = {}
        RemoteConnections.list.forEach(c => p[c.id] = exp.preselect.length === 0 || exp.preselect.includes(c.id))
        picked = p
    }

    readonly property var ids: RemoteConnections.list.filter(c => picked[c.id]).map(c => c.id)
    readonly property bool anyKeyring: RemoteConnections.list.some(c => picked[c.id] && c.password === "keyring")

    function save() {
        Jobs.run(["zenity", "--file-selection", "--save", "--title=Export connections",
                  "--filename=" + Quickshell.env("HOME") + "/quickshell-connections.json",
                  "--file-filter=JSON | *.json", "--file-filter=All files | *"], (code, out) => {
            const path = out.trim()
            if (code !== 0 || path === "") {
                if (code !== 1) { exp.error = true; exp.message = code === 127 ? "zenity isn't installed: " + Jobs.installHint("zenity") : "the file picker failed (" + code + ")" }
                return
            }
            RemoteConnections.exportTo(path, exp.ids, exp.withPasswords && exp.anyKeyring, (ok, msg) => {
                exp.error = !ok
                exp.message = ok ? "Saved " + exp.ids.length + " to " + path.replace(Quickshell.env("HOME"), "~") : msg
            })
        })
    }

    spacing: 0

    Repeater {
        model: RemoteConnections.list
        NetRow {
            id: row
            required property var modelData
            required property int index
            first: index === 0
            label: RemoteConnections.types[modelData.type].icon + "  " + modelData.name
            desc: (modelData.user ? modelData.user + "@" : "") + modelData.host + ":" + modelData.port
                  + (modelData.password === "keyring" ? "  ·  password in keyring" : "")
            ToggleSwitch {
                checked: exp.picked[row.modelData.id] ?? false
                onToggled: v => { const p = Object.assign({}, exp.picked); p[row.modelData.id] = v; exp.picked = p }
            }
        }
    }

    NetRow {
        visible: exp.anyKeyring
        label: "Include passwords"
        desc: exp.withPasswords ? "󰀦  the keyring passwords go into the file as plain text: anyone with the file can read them"
                                : "off: imported connections need their password set again"
        descError: exp.withPasswords
        ToggleSwitch { checked: exp.withPasswords; onToggled: v => exp.withPasswords = v }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 14
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: exp.message
            color: exp.error ? Colors.red : Colors.fade(0.6)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }
        ActionButton { text: "Close"; onClicked: exp.done() }
        ActionButton {
            icon: "󰈝"
            text: "Export " + exp.ids.length
            primary: true
            interactive: exp.ids.length > 0
            onClicked: exp.save()
        }
    }
}
