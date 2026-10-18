import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Import from ~/.config/custom/scripts/*.sh (xfreerdp3 / vncviewer lines) and
// ~/.ssh/config (Host entries). A plain-text /p: password in a script goes to
// the keyring; the script itself is not changed.
ColumnLayout {
    id: imp
    signal done()

    property var cands: []
    property var picked: ({})              // index → bool
    property bool scanning: true
    property string message: ""

    Component.onCompleted: RemoteConnections.scanImports(found => {
        imp.cands = found
        const p = {}
        found.forEach((r, i) => p[i] = !r.exists && Object.keys(r.errors).length === 0)
        imp.picked = p
        imp.scanning = false
    })

    readonly property int count: Object.keys(picked).filter(k => picked[k]).length
    readonly property bool anyPassword: cands.some((r, i) => picked[i] && r.password !== "")

    spacing: 0

    NetRow {
        first: true
        visible: imp.scanning || imp.cands.length === 0
        label: imp.scanning ? "Looking…" : "Nothing found"
        desc: "~/.config/custom/scripts/*.sh and ~/.ssh/config"
    }

    Repeater {
        model: imp.cands
        NetRow {
            id: row
            required property var modelData
            required property int index
            readonly property var r: modelData
            readonly property bool bad: Object.keys(r.errors).length > 0
            first: index === 0
            label: RemoteConnections.types[r.conn.type].icon + "  " + r.conn.name
            desc: (r.conn.user ? r.conn.user + "@" : "") + r.conn.host + ":" + r.conn.port + "  ·  " + r.source
                  + (r.password !== "" ? "  ·  password → keyring" : r.conn.password === "ask" ? "  ·  asks for the password" : "")
                  + (r.exists ? "  ·  already saved" : "")
                  + (row.bad ? "  ·  can't import: " + Object.values(r.errors).join(", ") : "")
            ToggleSwitch {
                checked: imp.picked[row.index] ?? false
                visible: !row.bad
                onToggled: v => { const p = Object.assign({}, imp.picked); p[row.index] = v; imp.picked = p }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.topMargin: 10
        visible: imp.anyPassword
        text: "󰀦  Your scripts keep their plain-text passwords. Once the import works, remove /p:… from them yourself"
              + " (and change any password that was ever pushed to a git repository)."
        color: Colors.yellow
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 14
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: imp.message
            color: Colors.red
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }
        ActionButton { text: "Close"; onClicked: imp.done() }
        ActionButton {
            icon: "󰋺"
            text: "Import " + imp.count
            primary: true
            interactive: imp.count > 0
            onClicked: RemoteConnections.importAll(imp.cands.filter((r, i) => imp.picked[i]), problems => {
                if (problems.length > 0) imp.message = "Imported, but: " + problems.join("; ")
                else imp.done()
            })
        }
    }
}
