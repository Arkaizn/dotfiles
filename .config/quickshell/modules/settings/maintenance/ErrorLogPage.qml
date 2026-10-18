import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Error log: the system journal's errors (or warnings) of this or the previous
// boot, optionally for one service, plus the shell's own warnings. Read-only.
ColumnLayout {
    id: page
    spacing: 16

    property string source: "journal"       // "journal" | "shell"
    property string level: "err"            // err | warning
    property string boot: "0"               // 0 = this boot, -1 = previous
    property string unit: ""
    property string filter: ""
    property var entries: []                // [{ time, who, text, prio }]
    property string error: ""
    readonly property bool loading: Jobs.isRunning("errlog")
    readonly property var shown: {
        const q = filter.trim().toLowerCase()
        return q === "" ? entries : entries.filter(e => (e.who + " " + e.text).toLowerCase().includes(q))
    }

    Component.onCompleted: load()
    Component.onDestruction: Jobs.cancel("errlog")

    function load() {
        error = ""
        entries = []
        if (source === "shell") {
            Jobs.start("errlog", ["qs", "log", "-n"], {
                timeout: 30000, maxLines: 20000,
                onExit: () => {
                    const lines = Jobs.state("errlog").lines.map(l => l.text.replace(/\x1b\[[0-9;]*m/g, ""))
                    entries = lines.filter(l => /^\s*(WARN|ERROR)/.test(l)).map(l => {
                        const m = /^\s*(WARN|ERROR)\s+(\S+?):?\s+(.*)$/.exec(l)
                        return m ? { time: "", who: m[2], text: m[3], prio: m[1] === "ERROR" ? 3 : 4 } : { time: "", who: "", text: l.trim(), prio: 4 }
                    }).reverse().slice(0, 400)
                }
            })
            return
        }
        if (unit !== "" && !/^[A-Za-z0-9@._:\\-]+$/.test(unit)) { error = "service name: letters, digits, @ . _ : - only"; return }
        // --all: without it journalctl leaves out messages over 4 KB (e.g. crash reports)
        const args = ["journalctl", "-p", level, "-b", boot, "-n", "400", "--no-pager", "-o", "json", "-r", "--all"]
        if (unit !== "") args.push("-u", unit)
        Jobs.start("errlog", args, {
            timeout: 60000, maxLines: 400,
            onExit: code => {
                const out = []
                for (const l of Jobs.state("errlog").lines) {
                    if (l.err) continue
                    try {
                        const j = JSON.parse(l.text)
                        let msg = j.MESSAGE
                        if (Array.isArray(msg)) msg = String.fromCharCode.apply(null, msg.slice(0, 2000))
                        const t = new Date(Number(j.__REALTIME_TIMESTAMP) / 1000)
                        out.push({ time: Qt.formatDateTime(t, "MM-dd HH:mm:ss"), who: j.SYSLOG_IDENTIFIER || j._SYSTEMD_UNIT || j._COMM || "?",
                                   text: String(msg ?? "").split("\n").find(x => x.trim() !== "")?.slice(0, 400) ?? "", prio: Number(j.PRIORITY ?? 3) })
                    } catch (e) {}
                }
                entries = out
                if (code !== 0 && out.length === 0) error = Jobs.state("errlog").lines.filter(l => l.err).map(l => l.text).slice(-2).join(" ") || "journalctl failed"
            }
        })
    }

    NetCard {
        Layout.fillWidth: true
        title: "Show"
        NetRow {
            first: true
            label: "Source"
            Segmented {
                small: true
                options: [{ label: "System journal", value: "journal" }, { label: "Shell (quickshell)", value: "shell" }]
                value: page.source
                onEdited: v => { page.source = v; page.load() }
            }
        }
        NetRow {
            visible: page.source === "journal"
            label: "Level and boot"
            RowLayout {
                spacing: 8
                Segmented {
                    small: true
                    options: [{ label: "Errors", value: "err" }, { label: "+ warnings", value: "warning" }]
                    value: page.level
                    onEdited: v => { page.level = v; page.load() }
                }
                Segmented {
                    small: true
                    options: [{ label: "This boot", value: "0" }, { label: "Previous", value: "-1" }]
                    value: page.boot
                    onEdited: v => { page.boot = v; page.load() }
                }
            }
        }
        NetRow {
            visible: page.source === "journal"
            label: "Only one service"
            desc: "e.g. NetworkManager, bluetooth, sddm (empty = all)"
            SearchField {
                Layout.preferredWidth: 220
                icon: ""
                placeholderText: "service name"
                text: page.unit
                onTextEdited: page.unit = text
                onAccepted: page.load()
            }
        }
        NetRow {
            label: "Search in the results"
            SearchField {
                Layout.preferredWidth: 220
                text: page.filter
                onTextEdited: page.filter = text
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: page.loading ? "Loading…" : page.shown.length + " entries" + (page.entries.length >= 400 ? " (newest 400)" : "")
        header: [
            ActionButton { icon: "󰆏"; text: "Copy"; interactive: page.shown.length > 0
                onClicked: Quickshell.execDetached(["wl-copy", "--", page.shown.map(e => (e.time ? e.time + " " : "") + e.who + ": " + e.text).join("\n")]) },
            ActionButton { icon: "󰑓"; text: "Reload"; onClicked: page.load() }
        ]
        NetRow { first: true; visible: page.error !== ""; label: "Problem"; desc: page.error }
        NetRow { first: true; visible: page.error === "" && !page.loading && page.shown.length === 0; label: "Nothing here"; desc: "no entries match" }
        Repeater {
            model: page.shown.slice(0, 200)
            Item {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: line.implicitHeight + 10
                RowLayout {
                    id: line
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                    spacing: 10
                    Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 4; implicitWidth: 6; implicitHeight: 6; radius: 3; color: modelData.prio <= 3 ? "#f38ba8" : "#f9e2af" }
                    Text { Layout.alignment: Qt.AlignTop; text: modelData.time; visible: modelData.time !== ""; color: Qt.rgba(1, 1, 1, 0.4); font.pixelSize: 11; font.family: Properties.fontFamily }
                    Text { Layout.alignment: Qt.AlignTop; Layout.preferredWidth: 130; text: modelData.who; color: Colors.color6; font.pixelSize: 11; font.family: Properties.fontFamily; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: modelData.text; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 11; font.family: Properties.fontFamily; wrapMode: Text.WrapAnywhere; maximumLineCount: 4; elide: Text.ElideRight }
                }
            }
        }
    }
}
