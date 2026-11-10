import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Export / import of the Servers app's list — how it gets to another device
// (servers.json is local and never synced). Export: one JSON file with the
// servers, groups, waves and saved commands (servers.json holds no secrets).
// Import: such a file, an svs.conf (manage-svs.sh conf-json) or the hosts of
// ~/.ssh/config; pick the servers, then add / overwrite / replace everything.
//   TransferDialog { id: t }   t.start("export" | "import")
Modal {
    id: root

    cardWidth: 620
    property string mode: "export"
    property string source: "file"          // file | conf | ssh
    property string path: ""
    property var cands: null                // { doc, list, error }
    property var picked: []
    property string how: "skip"             // skip | overwrite | replace
    property string message: ""
    property bool busy: false

    function start(m) {
        mode = m === "import" ? "import" : "export"
        message = ""
        cands = null
        picked = []
        path = mode === "export" ? ServerStore.home + "/servers-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".json" : ""
        open()
    }

    function choose() {
        Jobs.pickFile(mode === "export" ? { title: "Export servers to", save: true, start: path, filters: ["JSON | *.json"] }
                    : source === "conf" ? { title: "An svs.conf", start: ServerStore.dataDir + "/", filters: ["Config | *.conf"] }
                    : { title: "A servers export", start: ServerStore.home + "/", filters: ["JSON | *.json"] }, (p, err) => {
            if (err) message = err
            else if (p) { path = p; if (mode === "import") load() }
        })
    }
    function exportNow() {
        if (!path) return
        busy = true
        Jobs.runInput(["sh", "-c", 'umask 077; cat > "$1"', "sh", path], JSON.stringify(ServerStore.exportDoc(), null, 2) + "\n", code => {
            busy = false
            message = code === 0 ? "Exported " + ServerStore.servers.length + " servers to " + path : "Couldn't write " + path
        })
    }
    function load() {
        message = ""
        cands = null
        const done = c => { cands = c; picked = c.list.filter(x => !x.exists).map(x => x.server.name); if (c.error) message = c.error }
        if (source === "ssh") ServerStore.readSshConfig(done)
        else if (!path) return
        else if (source === "conf") ServerStore.readConf(path, done)
        else ServerStore.readImportFile(path, done)
    }
    function importNow() {
        if (!cands?.doc || picked.length === 0) return
        const r = ServerStore.importDoc(cands.doc, picked, how)
        message = "Imported: " + r.added + " added" + (r.replaced ? ", " + r.replaced + " replaced" : "")
        load()
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: root.mode === "export" ? "󰈝" : "󰋺"; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Segmented {
                    small: true
                    options: [{ label: "Export", value: "export", icon: "󰈝" }, { label: "Import", value: "import", icon: "󰋺" }]
                    value: root.mode
                    onEdited: v => root.start(v)
                }
                Text { Layout.fillWidth: true; text: "servers.json stays on this device: this file is how the list gets to another one"
                       color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        Segmented {
            visible: root.mode === "import"
            Layout.fillWidth: true
            options: [{ label: "Export file", value: "file", icon: "󰈔" }, { label: "svs.conf", value: "conf", icon: "󰒓" }, { label: "~/.ssh/config", value: "ssh", icon: "󰣀" }]
            value: root.source
            onEdited: v => { root.source = v; root.path = v === "conf" ? ServerStore.dataDir + "/svs.conf" : ""; root.cands = null; root.message = ""; if (v === "ssh") root.load() }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !(root.mode === "import" && root.source === "ssh")
            spacing: Tokens.space.s8
            SearchField {
                Layout.fillWidth: true
                icon: "󰈔"; clearable: false
                placeholderText: root.mode === "export" ? "Where to save it" : "Which file"
                text: root.path
                onTextChanged: root.path = text
                onAccepted: root.mode === "export" ? root.exportNow() : root.load()
            }
            ActionButton { icon: "󰉋"; text: "Choose…"; onClicked: root.choose() }
            ActionButton { visible: root.mode === "import"; icon: "󰑓"; text: "Read"; interactive: root.path !== ""; onClicked: root.load() }
        }

        // what's in it: pick the servers
        Flickable {
            visible: root.mode === "import" && (root.cands?.list ?? []).length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 260)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SlimScrollBar {}
            ColumnLayout {
                id: list
                width: parent.width - 14
                spacing: 1
                Repeater {
                    model: root.cands?.list ?? []
                    Checkbox {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.server.name + "   " + ServerStore.destOf(modelData.server) + ":" + modelData.server.port
                               + (modelData.server.checks.length ? "  ·  " + modelData.server.checks.length + " checks" : "")
                               + (modelData.exists ? "   (already here)" : "")
                        checked: root.picked.includes(modelData.server.name)
                        onClicked: root.picked = checked ? root.picked.filter(n => n !== modelData.server.name) : root.picked.concat([modelData.server.name])
                    }
                }
            }
        }
        Segmented {
            visible: root.mode === "import" && (root.cands?.list ?? []).length > 0
            Layout.fillWidth: true
            options: [{ label: "Add new ones", value: "skip" }, { label: "Add + overwrite existing", value: "overwrite" }, { label: "Replace the whole list", value: "replace" }]
            value: root.how
            onEdited: v => root.how = v
        }

        Text {
            Layout.fillWidth: true
            visible: root.message !== ""
            text: root.message
            color: /^(Exported|Imported)/.test(root.message) ? Colors.green : Colors.red
            font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Close"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                visible: root.mode === "export"
                icon: "󰈝"; text: "Export " + ServerStore.servers.length + " servers"; variant: "primary"
                busy: root.busy; interactive: root.path !== "" && ServerStore.servers.length > 0
                onClicked: root.exportNow()
            }
            ActionButton {
                visible: root.mode === "import"
                icon: "󰋺"
                text: root.how === "replace" ? "Replace with " + root.picked.length : "Import " + root.picked.length
                variant: root.how === "replace" ? "danger" : "primary"
                interactive: root.picked.length > 0
                onClicked: root.importNow()
            }
        }
    }
}
