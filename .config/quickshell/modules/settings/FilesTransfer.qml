import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// The file manager's bookmarks and preferences to / from a file (Settings → Apps
// → Files), the way the settings export works: pick what goes in, then where.
// Import: the file first, then what's in it to take (all of it by default);
// it adds to what's here — bookmarks, groups, servers, starred — and nothing
// goes. The preferences are this shell's (Settings.files, checked against
// FmSettings); the rest belongs to the file manager's process, asked through
// its IPC (FileManager.call: transferData / transferApply). Format: FmTransfer.
//   FilesTransfer { }   startExport() · startImport()
Modal {
    id: root

    cardWidth: 560

    property bool importing: false
    property var picked: ({})
    property var counts: ({})              // import: part → how many in the file
    property var doc: null                 // import: the checked file
    property string fileName: ""
    property string message: ""
    property bool error: false
    property bool busy: false
    property bool finished: false          // done: only Close is left

    readonly property var parts: importing ? FmTransfer.PARTS.filter(p => counts[p] !== undefined) : FmTransfer.PARTS
    readonly property var chosen: parts.filter(p => picked[p])

    function _reset(imp) {
        importing = imp
        message = ""; error = false; busy = false; finished = false
        const p = {}
        for (const k of FmTransfer.PARTS) p[k] = true
        picked = p
    }
    function _say(text, bad) { message = text; error = bad === true; busy = false }
    function toggle(k) { const p = Object.assign({}, picked); p[k] = !p[k]; picked = p }

    // ── Export: what's picked, then where ──
    function startExport() {
        _reset(false)
        counts = {}; doc = null; fileName = ""
        open()
    }
    function exportNow() {
        const want = chosen
        Jobs.pickFile({ title: "Export the file manager's bookmarks and preferences", save: true,
                        start: Quickshell.env("HOME") + "/quickshell-files.json", filters: ["JSON | *.json"] }, (path, err) => {
            if (path === "") { if (err) root._say(err, true); return }
            root.busy = true
            const write = src => {
                const text = JSON.stringify(FmTransfer.build(want, src, new Date().toISOString()), null, 2) + "\n"
                Jobs.runInput(["sh", "-c", 'umask 077 && cat > "$1"', "sh", path], text, (code, out, e) => {
                    if (code !== 0) { root._say("Couldn't write " + path + ": " + String(e ?? "").trim(), true); return }
                    root._say("Saved to " + path.replace(Quickshell.env("HOME"), "~"))
                    root.finished = true
                })
            }
            const settings = {}
            for (const it of FmSettings.items) if (Settings.files[it.key] !== undefined) settings[it.key] = Settings.files[it.key]
            // only the preferences: no need to start the file manager
            if (want.every(p => p === "settings")) { write({ settings: settings }); return }
            FileManager.call("transferData", [], (answer, e) => {
                let data = null
                try { data = answer ? JSON.parse(answer) : null } catch (x) {}
                if (!data) { root._say(e || "The file manager's answer wasn't readable", true); return }
                write(Object.assign(data, { settings: settings }))
            })
        })
    }

    // ── Import: the file, then what of it ──
    function startImport() {
        Jobs.pickFile({ title: "Import the file manager's bookmarks and preferences", start: Quickshell.env("HOME") + "/",
                        filters: ["JSON | *.json"] }, (path, err) => {
            if (path === "") { if (err) Jobs.run(["notify-send", "-a", "Settings", "Import", err]); return }
            // at most 4 MiB (an export is a few KB): one byte more says it's bigger
            Jobs.run(["head", "-c", "4194305", "--", path], (code, text, e) => {
                root._reset(true)
                root.fileName = path.replace(Quickshell.env("HOME"), "~")
                root.doc = null; root.counts = {}
                root.open()
                if (code !== 0) { root._say("Couldn't read it: " + String(e ?? "").trim(), true); root.finished = true; return }
                if (text.length > 4194304) { root._say("It's bigger than 4 MiB — not an export of the file manager", true); root.finished = true; return }
                const r = FmTransfer.parse(text)
                if (r.error !== "") { root._say("It " + r.error, true); root.finished = true; return }
                // the preferences: only keys of the spec with fitting values
                const bad = r.problems.slice()
                if (r.doc.settings) {
                    const ok = {}
                    for (const k in r.doc.settings) {
                        const m = FmSettings.check(k, r.doc.settings[k])
                        if (m === "") ok[k] = r.doc.settings[k]
                        else if (bad.length < 20) bad.push(k + ": " + m)
                    }
                    r.doc.settings = ok
                }
                root.doc = r.doc
                root.counts = FmTransfer.count(r.doc)
                if (Object.keys(root.counts).length === 0) { root._say("There's nothing in it to import", true); root.finished = true; return }
                if (bad.length) root._say("Left out (not valid): " + bad.join(" · "), true)
            })
        })
    }
    function importNow() {
        const want = chosen
        busy = true
        const did = []
        if (want.includes("settings")) {
            const s = doc.settings
            for (const k in s) Settings.set("files", k, s[k])
            did.push(Object.keys(s).length + " preferences")
        }
        const rest = want.filter(p => p !== "settings")
        if (rest.length === 0) { _done(did); return }
        // the file manager takes its part from a file of ours (checked again there)
        const sub = { quickshellFiles: 1 }
        for (const p of rest) {
            if (p === "bookmarks") { sub.bookmarks = doc.bookmarks; sub.groups = doc.groups; sub.groupPins = doc.groupPins }
            else sub[p] = doc[p]
        }
        Jobs.runInput(["sh", "-c", 'umask 077 && f=$(mktemp -p "${XDG_RUNTIME_DIR:?}" qs-files-import.XXXXXX) && cat > "$f" && printf %s "$f"', "sh"],
                      JSON.stringify(sub), (code, tmp, e) => {
            if (code !== 0 || tmp.trim() === "") { root._say("Couldn't hand it over: " + String(e ?? "").trim(), true); return }
            tmp = tmp.trim()
            FileManager.call("transferApply", [tmp, rest.join(",")], (answer, err) => {
                Jobs.run(["rm", "-f", "--", tmp], () => {})
                if (!answer.startsWith("ok ")) { root._say((did.length ? "Preferences imported, but the rest failed: " : "") + (err || answer), true); return }
                let r = {}
                try { r = JSON.parse(answer.slice(3)) } catch (x) {}
                const n = (v, one, many) => v + " " + (v === 1 ? one : many)
                if (r.bookmarks !== undefined) did.push(n(r.bookmarks, "new bookmark", "new bookmarks") + (r.groups ? ", " + n(r.groups, "group", "groups") : ""))
                if (r.servers !== undefined) did.push(n(r.servers, "new server", "new servers"))
                if (r.starred !== undefined) did.push(n(r.starred, "starred item", "starred items"))
                if (r.views) did.push("the views")
                root._done(did)
            })
        })
    }
    function _done(did) {
        _say("Imported: " + did.join(", ") + ". What was here already stays.")
        finished = true
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s10
            Text { text: root.importing ? "󰋺" : "󰈝"; color: Colors.color6; font.pixelSize: Tokens.font.titleLarge; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.importing ? "Import into Files" : "Export from Files"
                    color: Colors.ink; font.pixelSize: Tokens.font.title; font.bold: true; font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.importing ? "From " + root.fileName : "Pick what goes into the file"
                    color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.importing
                    text: "Added to what's here — nothing is removed"
                    color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        ListCard {
            visible: root.parts.length > 0
            Repeater {
                model: root.parts
                ColumnLayout {
                    id: part
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Divider { visible: part.index > 0 }
                    PlainRow {
                        Layout.fillWidth: true
                        label: FmTransfer.labels[part.modelData]
                        desc: root.importing ? (part.modelData === "views" ? "Sort, icon sizes, columns, sidebar order — replace yours"
                                                : part.modelData === "settings" ? root.counts.settings + " in the file — replace yours"
                                                : root.counts[part.modelData] + " in the file")
                            : ({ settings: "Everything in Settings → Files", bookmarks: "The sidebar's bookmarks, their groups and colours",
                                 servers: "Server addresses (never a password)", starred: "Starred files and folders (their paths)",
                                 views: "Default sort, icon sizes, list columns, the sidebar's order" })[part.modelData]
                        ToggleSwitch {
                            checked: root.picked[part.modelData] === true
                            enabled: !root.busy && !root.finished
                            onToggled: root.toggle(part.modelData)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space.s4
            spacing: Tokens.space.s8
            Text {
                Layout.fillWidth: true
                text: root.busy ? (root.importing ? "Importing…" : "Exporting…") : root.message
                color: root.error ? Colors.red : Colors.fade(0.6)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            ActionButton { text: root.finished ? "Close" : "Cancel"; onClicked: root.close() }
            ActionButton {
                visible: !root.finished
                icon: root.importing ? "󰋺" : "󰈝"
                text: root.importing ? "Import" : "Export…"
                primary: true
                interactive: root.chosen.length > 0 && !root.busy
                onClicked: root.importing ? root.importNow() : root.exportNow()
            }
        }
    }
}
