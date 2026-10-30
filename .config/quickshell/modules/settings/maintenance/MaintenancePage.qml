import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."

// Maintenance overview: every maintenance tool of the settings app as a tile
// with a quick status (read-only, cheap commands; nothing needs a password),
// so you see at a glance what needs attention. Click a tile to open the tool.
//   tools: the pages with parent "maintenance" (SettingsWindow.qml)
// A new tool only needs `parent: "maintenance"` there; give it a status in
// status() below if there's a cheap way to tell.
ColumnLayout {
    id: page
    spacing: 16

    property var tools: []
    signal openPage(string id)

    readonly property string home: Quickshell.env("HOME")

    // one entry per tool id: { level: "ok" | "warn" | "error" | "info" | "busy", text }
    property var info: ({})
    function put(id, level, text) {
        const o = Object.assign({}, info)
        o[id] = { level: level, text: text }
        info = o
    }

    Component.onCompleted: refresh()

    function refresh() {
        info = ({})
        if (Health.results.length === 0 && !Health.running) Health.run()
        if (Updates.lastCheck === 0 && !Updates.checking) Updates.refresh()
        Dotfiles.refresh()

        Jobs.run(["pacman", "-Qdtq"], (c, o) => {
            const n = o.split("\n").filter(x => x).length
            Jobs.run(["du", "-sb", "--", home + "/.local/share/Trash", (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache")], (c2, o2) => {
                const sizes = o2.split("\n").map(l => Number(l.split("\t")[0]) || 0)
                const parts = [n === 0 ? "no orphans" : n + (n === 1 ? " orphan" : " orphans"),
                               "cache " + Format.bytes(sizes[1] ?? 0), "trash " + (sizes[0] ? Format.bytes(sizes[0]) : "empty")]
                put("cleanup", n > 0 || (sizes[0] ?? 0) > 1073741824 ? "warn" : "ok", parts.join("  ·  "))
            })
        })
        Jobs.run(["df", "-B1", "--output=size,avail,target", "/", home], (c, o) => {
            const rows = o.split("\n").slice(1).map(l => l.trim().split(/\s+/)).filter(f => f.length === 3)
                          .filter((f, i, all) => all.findIndex(x => x[2] === f[2]) === i)
            if (rows.length === 0) return put("diskusage", "info", "")
            const worst = Math.max(...rows.map(f => 1 - Number(f[1]) / Number(f[0])))
            put("diskusage", worst > 0.95 ? "error" : worst > 0.85 ? "warn" : "ok",
                rows.map(f => f[2].replace(home, "~") + " " + Format.bytes(Number(f[1])) + " free").join("  ·  "))
        })
        let failed = 0, pending = 2
        for (const user of [false, true])
            Jobs.run(["systemctl"].concat(user ? ["--user"] : []).concat(["--failed", "--no-legend", "--plain", "--no-pager"]), (c, o) => {
                failed += o.split("\n").filter(x => x.trim()).length
                if (--pending === 0) put("services", failed > 0 ? "error" : "ok", failed === 0 ? "none failed" : failed + " failed")
            })
        Jobs.run(["journalctl", "-b", "-p", "3", "-q", "--no-pager", "-o", "cat", "-n", "1000"], (c, o) => {
            const n = o.split("\n").filter(x => x.trim()).length
            put("errorlog", n > 0 ? "warn" : "ok", n === 0 ? "no errors this boot" : (n >= 1000 ? "1000+" : n) + (n === 1 ? " error" : " errors") + " this boot")
        })
        Jobs.run(["systemd-analyze"], (c, o) => {
            const m = /=\s*([^\n]+?)\s*$/m.exec(o.split("\n")[0] ?? "")
            put("boottime", "info", m ? "last boot took " + m[1] : "still booting, or not available")
        })
        Jobs.run(["stat", "-c", "%Y", "/etc/pacman.d/mirrorlist"], (c, o) => {
            if (c !== 0) return put("mirrors", "info", "no mirrorlist")
            const d = Math.floor((Date.now() / 1000 - Number(o)) / 86400)
            put("mirrors", d > 60 ? "warn" : "ok", "refreshed " + (d < 1 ? "today" : d === 1 ? "yesterday" : d + " days ago"))
        })
        Jobs.run(["lsblk", "-d", "-n", "-o", "TYPE"], (c, o) => {
            const n = o.split("\n").filter(t => t.trim() === "disk").length
            put("diskhealth", "info", n + (n === 1 ? " drive" : " drives") + "  ·  reading SMART asks for your password")
        })
    }

    // live services feed these directly
    function status(id) {
        switch (id) {
        case "health":
            if (Health.running || Health.results.length === 0) return { level: "busy", text: "checking…" }
            return Health.errors > 0 ? { level: "error", text: Health.errors + (Health.errors === 1 ? " error" : " errors") + (Health.warnings ? ", " + Health.warnings + " warnings" : "") }
                 : Health.warnings > 0 ? { level: "warn", text: Health.warnings + (Health.warnings === 1 ? " warning" : " warnings") }
                 : { level: "ok", text: "everything works" }
        case "updates": {
            if (Updates.checking && Updates.lastCheck === 0) return { level: "busy", text: "checking…" }
            const parts = [Updates.count === 0 ? "up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates")]
            if (Updates.rebootNeeded) parts.push("reboot needed")
            if (Updates.pacnew.length > 0) parts.push(Updates.pacnew.length + " .pacnew")
            return { level: Updates.rebootNeeded || Updates.pacnew.length > 0 ? "warn" : Updates.count > 0 ? "info" : "ok", text: parts.join("  ·  ") }
        }
        case "dotfiles":
            if (!Dotfiles.isRepo) return { level: Dotfiles.loading ? "busy" : "info", text: Dotfiles.loading ? "reading…" : "no repo set up" }
            if (Dotfiles.files.length > 0 || Dotfiles.ahead > 0 || Dotfiles.behind > 0)
                return { level: "warn", text: [Dotfiles.files.length ? Dotfiles.files.length + " uncommitted" : "", Dotfiles.ahead ? Dotfiles.ahead + " to push" : "",
                                               Dotfiles.behind ? Dotfiles.behind + " to pull" : ""].filter(x => x).join("  ·  ") }
            return { level: "ok", text: "in sync" }
        case "diagnostics":
            return { level: "info", text: "ping, traceroute, ports, speed test" }
        }
        return info[id] ?? { level: "busy", text: "…" }
    }

    function levelColor(l) { return l === "ok" ? Colors.green : l === "warn" ? Colors.yellow : l === "error" ? Colors.red : Colors.fade(0.35) }

    readonly property var levels: tools.map(t => status(t.id).level)
    readonly property int attention: levels.filter(l => l === "warn" || l === "error").length

    // ── Animation ───────────────────────────────────────────────────────────
    // tiles come in one after another (on open and on Check again); a status
    // that changes pops its dot and fades its text in; the summary icon spins
    // while anything is still checking
    readonly property bool busy: levels.includes("busy")
    property int wave: 0                     // bumped to replay the entrance
    function recheck() { Health.run(); Updates.refresh(); refresh(); wave++ }

    // ── Summary ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        spacing: 10
        Text {
            id: sumIcon
            text: page.busy && page.attention === 0 ? "󰑓" : page.attention === 0 ? "󰄬" : "󰀦"
            color: page.busy && page.attention === 0 ? Colors.fade(0.5)
                 : page.attention === 0 ? Colors.green : page.levels.includes("error") ? Colors.red : Colors.yellow
            font.pixelSize: 18
            font.family: Properties.fontFamily
            Behavior on color { ColorAnimation { duration: 250 } }
            // spin while checking, back upright when done
            RotationAnimation on rotation {
                running: page.busy && page.attention === 0
                loops: Animation.Infinite
                from: 0; to: 360; duration: 900
                onRunningChanged: if (!running) sumIcon.rotation = 0
            }
            onTextChanged: iconPop.restart()
            NumberAnimation { id: iconPop; target: sumIcon; property: "scale"; from: 0.4; to: 1; duration: 380; easing.type: Easing.OutBack }
        }
        Text {
            id: sumText
            Layout.fillWidth: true
            text: page.busy && page.attention === 0 ? "Checking…"
                  : page.attention === 0 ? "Nothing needs attention" : page.attention + (page.attention === 1 ? " tool needs" : " tools need") + " a look"
            color: Colors.ink
            font.pixelSize: 14
            font.bold: true
            font.family: Properties.fontFamily
            onTextChanged: textIn.restart()
            ParallelAnimation {
                id: textIn
                NumberAnimation { target: sumText; property: "opacity"; from: 0; to: 1; duration: 260 }
                NumberAnimation { target: sumShift; property: "x"; from: -8; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
            transform: Translate { id: sumShift }
        }
        ActionButton { icon: "󰑓"; text: "Check again"; onClicked: page.recheck() }
    }

    // ── Tiles ───────────────────────────────────────────────────────────────
    GridLayout {
        id: grid
        Layout.fillWidth: true
        columns: Math.max(1, Math.floor((width + columnSpacing) / (250 + columnSpacing)))
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: page.tools
            Rectangle {
                id: tile
                required property var modelData
                required property int index
                readonly property var st: page.status(modelData.id)
                readonly property color accent: page.levelColor(st.level)
                readonly property bool alert: st.level === "warn" || st.level === "error"
                Layout.fillWidth: true
                Layout.preferredWidth: 250
                implicitHeight: tileCol.implicitHeight + 24
                radius: 14
                clip: true
                color: alert ? Qt.tint(Colors.card, Qt.rgba(accent.r, accent.g, accent.b, 0.06)) : Colors.card
                border.width: Properties.panelBorderWidth
                border.color: hover.hovered ? Colors.fade(0.2) : alert ? Qt.rgba(accent.r, accent.g, accent.b, 0.3) : Properties.cardBorder
                scale: tap.pressed ? Properties.onPressedButtonScale : hover.hovered ? 1.015 : 1
                Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 300 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                // entrance: fade + rise, staggered by position
                opacity: 0
                transform: Translate { id: rise; y: 16 }
                function enter() { entrance.restart() }
                Component.onCompleted: enter()
                Connections { target: page; function onWaveChanged() { tile.enter() } }
                SequentialAnimation {
                    id: entrance
                    PropertyAction { target: tile; property: "opacity"; value: 0 }
                    PropertyAction { target: rise; property: "y"; value: 16 }
                    PauseAnimation { duration: tile.index * 40 }
                    ParallelAnimation {
                        NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }
                        NumberAnimation { target: rise; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                // accent stripe on the left: grows in when the tile needs a look
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 12; bottomMargin: 12 }
                    width: 3
                    radius: 1.5
                    color: tile.accent
                    opacity: tile.alert ? 1 : 0
                    scale: tile.alert ? 1 : 0.2
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                }

                ColumnLayout {
                    id: tileCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
                    spacing: 4
                    RowLayout {
                        spacing: 9
                        Text {
                            text: tile.modelData.icon
                            color: Colors.color6
                            font.pixelSize: 17
                            font.family: Properties.fontFamily
                            // a little nudge on hover
                            rotation: hover.hovered ? -8 : 0
                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: tile.modelData.title
                            color: Colors.ink
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            id: dot
                            implicitWidth: 8; implicitHeight: 8; radius: 4
                            color: tile.accent
                            visible: tile.st.level !== "info"
                            Behavior on color { ColorAnimation { duration: 300 } }
                            SequentialAnimation on opacity {
                                running: tile.st.level === "busy"
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.3; duration: 600 }
                                NumberAnimation { to: 1; duration: 600 }
                            }
                            // the result is in: pop
                            readonly property string level: tile.st.level
                            onLevelChanged: if (level !== "busy") dotPop.restart()
                            NumberAnimation { id: dotPop; target: dot; property: "scale"; from: 2; to: 1; duration: 450; easing.type: Easing.OutBack }
                        }
                    }
                    Text {
                        id: statusText
                        Layout.fillWidth: true
                        text: tile.st.text
                        color: tile.alert ? tile.accent : Colors.fade(0.75)
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                        wrapMode: Text.WordWrap
                        Behavior on color { ColorAnimation { duration: 300 } }
                        onTextChanged: statusIn.restart()
                        NumberAnimation { id: statusIn; target: statusText; property: "opacity"; from: 0.15; to: 1; duration: 320; easing.type: Easing.OutCubic }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: tile.modelData.desc
                        color: Colors.fade(0.42)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: tap; onTapped: page.openPage(tile.modelData.id) }
            }
        }
    }
}
