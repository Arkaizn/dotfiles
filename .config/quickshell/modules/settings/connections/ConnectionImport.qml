import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Import from ~/.config/custom/scripts/*.sh (xfreerdp3 / vncviewer lines) and
// ~/.ssh/config (Host entries), or from a file made with Export. A plain-text
// /p: password in a script (or a password in an export file) goes to the
// keyring; the script itself is not changed.
ColumnLayout {
    id: imp
    signal done()

    property var cands: []
    property var picked: ({})              // index → bool
    property bool scanning: true
    property string message: ""
    property string fileName: ""           // set once candidates come from an export file
    property bool replace: true            // already saved (same name + type): replace it, or keep both

    function setCands(found) {
        cands = found
        const p = {}
        found.forEach((r, i) => p[i] = !r.exists && Object.keys(r.errors).length === 0)
        picked = p
    }
    function fromFile() {
        Jobs.run(["zenity", "--file-selection", "--title=Import connections", "--filename=" + Quickshell.env("HOME") + "/",
                  "--file-filter=JSON | *.json", "--file-filter=All files | *"], (code, out) => {
            const path = out.trim()
            if (code !== 0 || path === "") {
                if (code !== 1) imp.message = code === 127 ? "zenity isn't installed: " + Jobs.installHint("zenity") : "the file picker failed (" + code + ")"
                return
            }
            Jobs.run(["cat", "--", path], (c, text, err) => {
                if (c !== 0) { imp.message = err.trim() || "can't read " + path; return }
                const r = RemoteConnections.parseFile(text, path.replace(/.*\//, ""))
                imp.message = r.error
                if (r.error !== "") return
                imp.fileName = path.replace(Quickshell.env("HOME"), "~")
                imp.setCands(r.cands)
            })
        })
    }

    Component.onCompleted: RemoteConnections.scanImports(found => {
        if (imp.fileName === "") imp.setCands(found)
        imp.scanning = false
    })

    readonly property int count: Object.keys(picked).filter(k => picked[k]).length
    readonly property bool anyPassword: fileName === "" && cands.some((r, i) => picked[i] && r.password !== "")
    readonly property bool anyExisting: cands.some((r, i) => picked[i] && r.exists)

    spacing: 0

    NetRow {
        first: true
        label: imp.fileName !== "" ? "From " + imp.fileName : imp.scanning ? "Looking…" : imp.cands.length === 0 ? "Nothing found" : "Found in your scripts and ssh config"
        desc: imp.fileName !== "" ? "a file made with Export" : "~/.config/custom/scripts/*.sh and ~/.ssh/config"
        ActionButton { icon: "󰈔"; text: "From a file…"; onClicked: imp.fromFile() }
    }

    Repeater {
        model: imp.cands
        NetRow {
            id: row
            required property var modelData
            required property int index
            readonly property var r: modelData
            readonly property bool bad: Object.keys(r.errors).length > 0
            label: (RemoteConnections.types[r.conn.type]?.icon ?? "?") + "  " + r.conn.name
            desc: (r.conn.user ? r.conn.user + "@" : "") + r.conn.host + ":" + r.conn.port + "  ·  " + r.source
                  + (r.password !== "" ? "  ·  password → keyring" : r.conn.password === "ask" ? "  ·  asks for the password" : "")
                  + (r.noSecret ? "  ·  password not in the file: set it in the editor after importing" : "")
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

    NetRow {
        visible: imp.anyExisting
        label: "Already saved"
        desc: imp.replace ? "the imported one replaces the saved connection with the same name" : "the imported one is added next to it"
        Segmented {
            options: [{ label: "Replace", value: true }, { label: "Keep both", value: false }]
            value: imp.replace
            onEdited: v => imp.replace = v
        }
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
            }, imp.replace)
        }
    }
}
