import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath

// Properties (Ctrl+I, Alt+Enter, right-click): type, size (a folder's is counted
// in the background), contents, location, link target, image size, dates, the
// drive's free space; permissions like Nautilus (who may read / write, run as a
// program) — yours only; the owner through pkexec (the shell's password prompt).
// Several selected: how many, their size together.
//   PropsDialog { backend; onOpenLocation: path => … }   start(paths)
Modal {
    id: root

    required property var backend
    signal openLocation(string path)
    cardWidth: 520

    property var paths: []
    property var p: null                 // the backend's props (one item)
    property var du: null                // { size, disk, files, dirs } while / once counted
    property bool counting: false
    property string error: ""
    property int _duId: 0
    readonly property bool single: paths.length === 1
    readonly property bool isDir: single && p !== null && p.dir === true

    function start(list) {
        paths = list
        p = null; du = null; error = ""
        owner.shown = false
        open()
        if (single) load()
        measure()
    }
    function load() {
        backend.request("props", { path: paths[0] }, { done: res => root.p = res, error: msg => root.error = msg })
    }
    // folders (and several items): their size, counted through
    function measure() {
        if (_duId) backend.cancel(_duId)
        counting = true
        let id = 0
        id = backend.request("du", { paths: paths }, {
            progress: m => { if (id === root._duId) root.du = { size: m.bytes, files: m.done, dirs: 0, partial: true } },
            done: res => { if (id === root._duId) { root.du = res; root.counting = false } },
            error: () => { if (id === root._duId) root.counting = false }
        })
        _duId = id
    }
    onClosed: if (_duId) { backend.cancel(_duId); _duId = 0 }

    function when(t) { return t ? Qt.formatDateTime(new Date(t * 1000), "d MMM yyyy, hh:mm") : "" }

    // ── Permissions ──
    // per class (owner 6, group 3, others 0): a file's read / write, a folder's access level
    function level(shift) { return p ? (p.lmode >> shift) & 7 : 0 }
    readonly property var fileLevels: [{ label: "Read and write", value: 6 }, { label: "Read only", value: 4 }, { label: "None", value: 0 }]
    readonly property var dirLevels: [{ label: "Create and delete files", value: 7 }, { label: "Access files", value: 5 },
                                      { label: "List files only", value: 4 }, { label: "None", value: 0 }]
    function setLevel(shift, v) {
        const keepX = isDir ? 0 : (level(shift) & 1)
        const m = (p.lmode & ~(7 << shift)) | ((v | keepX) << shift)
        chmod(m)
    }
    readonly property bool exec: p ? (p.lmode & 0o100) !== 0 : false
    function setExec(on) {
        // like Nautilus: everyone who may read it may run it (or nobody)
        let m = p.lmode & ~0o111
        if (on) m |= ((p.lmode & 0o444) >> 2)
        chmod(m)
    }
    function chmod(m) {
        backend.request("chmod", { path: paths[0], mode: m }, { done: () => root.load(), error: msg => root.error = msg })
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: root.p ? FmIcons.item({ dir: root.p.dir, type: root.p.mime, exec: root.p.exec }) : FmIcons.g.file
                       color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text {
                    Layout.fillWidth: true
                    text: root.single ? FmFormat.shown(FmPath.base(root.paths[0] ?? "")) : root.paths.length + " items"
                    color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    text: root.p ? FmFormat.typeLabel({ dir: root.p.dir, type: root.p.mime }) + (root.p.mime && !root.p.dir ? "  ·  " + root.p.mime : "") : ""
                    color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; elide: Text.ElideRight
                }
            }
            IconButton { icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        Banner { visible: root.error !== ""; Layout.fillWidth: true; tone: "error"; text: root.error }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            PropRow {
                label: "Size"
                value: root.du ? Format.bytes(root.du.size) + (root.counting ? "  (counting…)" : "")
                                 + (root.du.disk ? "  ·  " + Format.bytes(root.du.disk) + " on disk" : "")
                     : root.p && !root.p.dir ? Format.bytes(root.p.size) : "…"
            }
            PropRow {
                label: "Contents"
                value: (root.isDir || !root.single) && root.du ? root.du.files + (root.du.files === 1 ? " file" : " files")
                       + (root.du.dirs > (root.isDir ? 1 : 0) ? ", " + (root.du.dirs - (root.isDir ? 1 : 0)) + " folders" : "") : ""
            }
            PropRow { label: "Image size"; value: root.p?.width ? root.p.width + " × " + root.p.height + " pixels" : "" }
            PropRow { label: "Link to"; value: root.p?.link ? root.p.target + (root.p.broken ? "  (missing)" : "") : "" }
            RowLayout {
                visible: root.single
                Layout.fillWidth: true
                spacing: Tokens.space.s12
                Text { Layout.preferredWidth: Tokens.size.row * 2.6; text: "Location"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: FmPath.parent(root.paths[0] ?? "/"); color: Colors.fade(0.88); font.pixelSize: Tokens.font.small
                       font.family: Properties.fontFamily; elide: Text.ElideMiddle; textFormat: Text.PlainText }
                ActionButton { text: "Open"; variant: "ghost"; onClicked: { root.close(); root.openLocation(root.paths[0]) } }
            }
            PropRow { label: "Modified"; value: root.when(root.p?.mtime) }
            PropRow { label: "Accessed"; value: root.when(root.p?.atime) }
            PropRow { label: "Changed"; value: root.when(root.p?.ctime) }
            PropRow { label: "Free space"; value: root.p?.free !== undefined ? Format.bytes(root.p.free) + " of " + Format.bytes(root.p.size ?? 0) : "" }
        }

        // ── Permissions (one item) ──
        ColumnLayout {
            visible: root.single && root.p !== null && !root.p.link
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            Text { text: "PERMISSIONS"; color: Colors.fade(0.4); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 0.6; font.family: Properties.fontFamily }
            Text {
                visible: root.p && !root.p.mine
                Layout.fillWidth: true
                text: "Only the owner (" + (root.p?.owner ?? "") + ") can change them"
                color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
            }
            Repeater {
                model: [["Owner (" + (root.p?.owner ?? "") + ")", 6], ["Group (" + (root.p?.group ?? "") + ")", 3], ["Others", 0]]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.space.s12
                    Text { Layout.preferredWidth: Tokens.size.row * 2.6; text: modelData[0]; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small
                           font.family: Properties.fontFamily; elide: Text.ElideRight }
                    Dropdown {
                        Layout.fillWidth: true
                        interactive: root.p?.mine === true
                        options: root.isDir ? root.dirLevels : root.fileLevels
                        value: root.isDir ? root.level(modelData[1]) : (root.level(modelData[1]) & 6)
                        onEdited: v => root.setLevel(modelData[1], v)
                    }
                }
            }
            RowLayout {
                visible: !root.isDir
                Layout.fillWidth: true
                spacing: Tokens.space.s12
                Text { Layout.fillWidth: true; text: "Allow running it as a program"; color: Colors.fade(0.8); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
                ToggleSwitch { checked: root.exec; interactive: root.p?.mine === true; accessibleName: "Executable"; onToggled: v => root.setExec(v) }
            }
            // the owner: as root, through pkexec (the shell's polkit agent asks for the password)
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s12
                Text { Layout.preferredWidth: Tokens.size.row * 2.6; text: "Owner"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: (root.p?.owner ?? "") + " : " + (root.p?.group ?? ""); color: Colors.fade(0.88)
                       font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; textFormat: Text.PlainText }
                ActionButton { text: owner.shown ? "Cancel" : "Change…"; variant: "ghost"; onClicked: { owner.shown = !owner.shown; ownerField.text = root.p?.owner ?? ""; groupField.text = root.p?.group ?? "" } }
            }
            RowLayout {
                id: owner
                property bool shown: false
                property bool busy: false
                visible: shown
                Layout.fillWidth: true
                spacing: Tokens.space.s6
                SearchField { id: ownerField; Layout.fillWidth: true; icon: ""; placeholderText: "user" }
                SearchField { id: groupField; Layout.fillWidth: true; icon: ""; placeholderText: "group" }
                Checkbox { id: recursive; visible: root.isDir; label: "With everything in it"; onClicked: checked = !checked }
                ActionButton {
                    text: "Apply"
                    variant: "primary"
                    busy: owner.busy
                    onClicked: {
                        owner.busy = true
                        root.backend.request("chown", { path: root.paths[0], owner: ownerField.text.trim(), group: groupField.text.trim(), recursive: recursive.checked }, {
                            done: () => { owner.busy = false; owner.shown = false; root.load() },
                            error: msg => { owner.busy = false; root.error = msg }
                        })
                    }
                }
            }
        }
    }
}
