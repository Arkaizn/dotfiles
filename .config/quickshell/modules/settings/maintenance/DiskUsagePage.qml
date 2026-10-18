import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Disk usage (like ncdu / TreeSize): what takes space in a folder, biggest
// first; click a folder to go into it. Scans with gdu (fast, parallel), stays
// on one file system, can be stopped. Items under your home folder can be
// moved to the trash (two clicks); nothing is deleted for good here.
ColumnLayout {
    id: page
    spacing: 16

    readonly property string home: Quickshell.env("HOME")
    property string path: home
    property var items: []                 // [{ name, size, dir }]
    property var cache: ({})               // path → items (going back is instant)
    property var bigFiles: []              // [{ path, size }]
    property string error: ""
    property string pathInput: home
    property string confirmTrash: ""
    readonly property bool scanning: Jobs.isRunning("du-scan")
    readonly property bool findingFiles: Jobs.isRunning("du-files")
    readonly property real total: items.reduce((a, i) => a + i.size, 0)

    Component.onCompleted: scan(home)
    Component.onDestruction: { Jobs.cancel("du-scan"); Jobs.cancel("du-files") }

    function scan(p, fresh) {
        p = p.replace(/\/+$/, "") || "/"
        path = p
        pathInput = p
        error = ""
        bigFiles = []
        if (!fresh && cache[p]) { items = cache[p]; return }
        items = []
        Jobs.start("du-scan", ["gdu", "-n", "-p", "-c", "-x", "--no-prefix", "--", p], {
            timeout: 600000, maxLines: 100000,
            onExit: code => {
                const st = Jobs.state("du-scan")
                if (st.missing) { error = "gdu isn't installed: " + Jobs.installHint("gdu"); return }
                if (st.cancelled) { error = "stopped"; return }
                const list = []
                for (const l of st.lines) {
                    if (l.err) continue
                    const m = /^\s*(\d+)\s+(\/?)(.+)$/.exec(l.text)
                    if (m) list.push({ name: m[3], size: Number(m[1]), dir: m[2] === "/" })
                }
                list.sort((a, b) => b.size - a.size)
                items = list
                const c = Object.assign({}, cache); c[p] = list; cache = c
                if (code !== 0 && list.length === 0) error = st.lines.filter(l => l.err).map(l => l.text).slice(-2).join(" ") || "can't read " + p
            }
        })
    }
    function up() { if (path !== "/") scan(path.replace(/\/[^/]+$/, "") || "/") }
    function child(name) { return (path === "/" ? "" : path) + "/" + name }

    // files over 50 MB anywhere below the folder (same file system)
    function findBig() {
        bigFiles = []
        Jobs.start("du-files", ["find", path, "-xdev", "-type", "f", "-size", "+50M", "-printf", "%s\\t%p\\n"], {
            timeout: 600000, maxLines: 100000,
            onExit: () => {
                bigFiles = Jobs.state("du-files").lines.filter(l => !l.err).map(l => l.text.split("\t"))
                    .filter(p => p.length === 2).map(p => ({ size: Number(p[0]), path: p[1] }))
                    .sort((a, b) => b.size - a.size).slice(0, 30)
            }
        })
    }

    // move to the trash (reversible) — only below your home folder
    function trash(p) {
        if (!p.startsWith(home + "/") || p.includes("/../")) return
        Jobs.run(["gio", "trash", "--", p], (code, out, err) => {
            if (code !== 0) { error = err.trim() || "couldn't move it to the trash"; return }
            const c = Object.assign({}, cache)
            for (const k in c) if (p.startsWith(k + "/") || k === p) delete c[k]   // sizes above changed
            cache = c
            scan(path, true)
        })
    }

    NetCard {
        Layout.fillWidth: true
        title: "Folder"
        NetRow {
            first: true
            wide: true
            label: page.scanning ? "Scanning " + page.path + " …" : page.path + "  ·  " + PerfMon.bytes(page.total)
            desc: page.error !== "" ? "󰀦 " + page.error : "stays on one file system (other disks and mounts are skipped)"
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconButton { icon: "󰁝"; tooltip: "Up"; interactive: page.path !== "/" && !page.scanning; onClicked: page.up() }
                IconButton { icon: "󰋜"; tooltip: "Home folder"; interactive: !page.scanning; onClicked: page.scan(page.home) }
                SearchField {
                    Layout.fillWidth: true
                    icon: "󰉋"
                    clearable: false
                    text: page.pathInput
                    onTextEdited: page.pathInput = text
                    onAccepted: if (page.pathInput.startsWith("/")) page.scan(page.pathInput)
                }
                ActionButton {
                    icon: page.scanning ? "󰜺" : "󰑓"
                    text: page.scanning ? "Stop" : "Rescan"
                    onClicked: page.scanning ? Jobs.cancel("du-scan") : page.scan(page.path, true)
                }
                ActionButton { icon: "󰉋"; text: "Open"; onClicked: Quickshell.execDetached(["xdg-open", page.path]) }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        visible: page.items.length > 0
        title: page.items.length + " items"
        Repeater {
            model: page.items.slice(0, 60)
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property string full: page.child(modelData.name)
                Layout.fillWidth: true
                implicitHeight: 40
                Rectangle {
                    anchors { fill: parent; leftMargin: 6; rightMargin: 6; topMargin: 2; bottomMargin: 2 }
                    radius: 8
                    color: hover.hovered && row.modelData.dir ? Colors.fade(0.06) : "transparent"
                    // size bar behind the row, relative to the biggest item
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * row.modelData.size / Math.max(1, page.items[0].size)
                        visible: width >= 4
                        radius: Math.min(8, width / 2)
                        color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.12)
                    }
                    HoverHandler { id: hover; cursorShape: row.modelData.dir ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: row.modelData.dir && !page.scanning; onTapped: page.scan(row.full) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                        spacing: 10
                        Text { text: row.modelData.dir ? "󰉋" : "󰈔"; color: row.modelData.dir ? Colors.color6 : Colors.fade(0.5); font.pixelSize: 15; font.family: Properties.fontFamily }
                        Text { Layout.fillWidth: true; text: row.modelData.name; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideMiddle }
                        Text { text: (page.total > 0 ? Math.round(100 * row.modelData.size / page.total) : 0) + " %"; color: Colors.fade(0.4); font.pixelSize: 11; font.family: Properties.fontFamily }
                        Text { Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; text: PerfMon.bytes(row.modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                        IconButton {
                            visible: row.full.startsWith(page.home + "/")
                            icon: page.confirmTrash === row.full ? "󰄬" : "󰩹"
                            textColor: page.confirmTrash === row.full ? Colors.red : Properties.color
                            tooltip: page.confirmTrash === row.full ? "Click again: move to the trash" : "Move to the trash"
                            onClicked: {
                                if (page.confirmTrash === row.full) { page.trash(row.full); page.confirmTrash = "" }
                                else { page.confirmTrash = row.full; trashTimer.restart() }
                            }
                        }
                    }
                }
            }
        }
        NetRow {
            visible: page.items.length > 60
            label: "… and " + (page.items.length - 60) + " smaller items"
        }
    }
    Timer { id: trashTimer; interval: 3000; onTriggered: page.confirmTrash = "" }

    NetCard {
        Layout.fillWidth: true
        title: "Biggest files"
        header: ActionButton {
            icon: page.findingFiles ? "󰜺" : "󰍉"
            text: page.findingFiles ? "Stop" : "Find files over 50 MB"
            onClicked: page.findingFiles ? Jobs.cancel("du-files") : page.findBig()
        }
        NetRow {
            first: true
            visible: page.bigFiles.length === 0
            label: page.findingFiles ? "Searching " + page.path + " …" : "Not searched yet"
            desc: "anywhere below this folder, on the same file system"
        }
        Repeater {
            model: page.bigFiles
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.path.replace(page.home, "~")
                RowLayout {
                    spacing: 6
                    Text { text: PerfMon.bytes(modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                    IconButton { icon: "󰉋"; tooltip: "Show the folder"; onClicked: Quickshell.execDetached(["xdg-open", modelData.path.replace(/\/[^/]*$/, "")]) }
                }
            }
        }
    }
}
