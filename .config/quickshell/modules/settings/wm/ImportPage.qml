import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Import page: moves things from your per-device custom configs into the
// settings (so they show up, can be switched on / off and travel with an
// export):
//   ~/.config/custom/niri/custom.kdl        autostart + keybinds
//   ~/.config/custom/hyprland/custom.lua   autostart + keybinds
// Commented-out lines come in switched off. Imported lines can be commented
// out in the file (default) so nothing runs twice; the file is backed up to
// ~/.local/state/quickshell/custom-backups first. Rules and anything else
// stay in the file and are listed as such.
ColumnLayout {
    id: page
    spacing: 16

    readonly property string home: Quickshell.env("HOME")
    readonly property string niriFile: home + "/.config/custom/niri/custom.kdl"
    readonly property string hyprFile: home + "/.config/custom/hyprland/custom.lua"
    readonly property string backupDir: home + "/.local/state/quickshell/custom-backups"

    property bool commentOut: true
    property var niri: ({ items: [], other: [], text: "", found: false })
    property var hypr: ({ items: [], other: [], text: "", found: false })
    property var picked: ({})              // item id → bool

    Component.onCompleted: reload()
    function reload() { niriRead.reload(); hyprProc.running = true }

    // ── niri: line by line ──────────────────────────────────────────────────
    FileView {
        id: niriRead
        path: page.niriFile
        printErrors: false
        onLoaded: page.niri = page.parseNiri(text())
        onLoadFailed: page.niri = ({ items: [], other: [], text: "", found: false })
    }

    function args(rest) {
        return NiriSettings.tokenize(rest).filter(t => t.t === "word" || t.t === "str").map(t => t.v)
    }

    function parseNiri(text) {
        const lines = text.split("\n")
        const items = [], other = []
        let depth = 0, bindsDepth = -1
        lines.forEach((line, i) => {
            const commented = /^\s*\/\//.test(line)
            const body = line.replace(/^(\s*)\/\/\s?/, "$1")
            let m = /^\s*(spawn-sh-at-startup|spawn-at-startup)\b(.*)$/.exec(body)
            if (m && depth === 0) {
                const a = args(m[2])
                const cmd = m[1] === "spawn-sh-at-startup" ? (a[0] ?? "")
                          : a[0] === "sh" && a[1] === "-c" ? (a[2] ?? "") : a.map(x => /\s/.test(x) ? "'" + x + "'" : x).join(" ")
                if (cmd) items.push({ id: "n" + i, kind: "autostart", cmd: cmd, enabled: !commented, line: i, label: cmd })
                return
            }
            if (bindsDepth >= 0 && depth === bindsDepth + 1) {
                m = /^\s*([^\s{]+)((?:\s+[\w-]+=(?:"[^"]*"|\S+))*)\s*\{(.*)\}\s*$/.exec(body)
                if (m && /[+A-Za-z0-9]/.test(m[1])) {
                    const title = (/hotkey-overlay-title="([^"]*)"/.exec(m[2]) ?? [])[1] ?? ""
                    const props = m[2].trim().replace(/\s*hotkey-overlay-title=(?:"[^"]*"|\S+)/, "").trim()
                    const action = m[3].trim().replace(/;\s*$/, "").trim()
                    const a = args(action)
                    const spawn = a[0] === "spawn-sh" ? a[1] : a[0] === "spawn" ? a.slice(1).join(" ") : ""
                    items.push({ id: "n" + i, kind: "bind", keys: m[1].split("+"), title: title, props: props,
                                 cmd: spawn, raw: spawn ? "" : action, enabled: !commented, line: i,
                                 label: m[1] + "  →  " + (title || spawn || action) })
                }
            }
            if (!commented) {
                // track blocks (braces outside strings) and what's at the top level
                const plain = line.replace(/"(?:[^"\\]|\\.)*"/g, "\"\"")
                if (depth === 0) {
                    const name = (/^\s*([\w-]+)/.exec(plain) ?? [])[1]
                    if (name === "binds") bindsDepth = 0
                    else if (name && !/^(spawn-sh-at-startup|spawn-at-startup)$/.test(name)) other.push(name + " (line " + (i + 1) + ")")
                }
                for (const c of plain) {
                    if (c === "{") depth++
                    else if (c === "}") { depth--; if (depth === bindsDepth) bindsDepth = -1 }
                }
            }
        })
        return { items: items, other: other, text: text, found: true }
    }

    // ── Hyprland: the Lua reader, items from custom.lua ─────────────────────
    Process {
        id: hyprProc
        command: ["lua", Quickshell.shellDir + "/scripts/hypr-binds.lua", HyprSettings.mainConfig]
        stdout: StdioCollector { id: hyprOut }
        onExited: {
            let d = {}
            try { d = JSON.parse(hyprOut.text) } catch (e) {}
            const f = page.hyprFile
            const items = []
            for (const a of d.autostart ?? []) if (a.file === f)
                items.push({ id: "h" + a.line + "a" + items.length, kind: "autostart", cmd: a.cmd, enabled: true, line: a.line - 1, label: a.cmd })
            for (const b of d.binds ?? []) if (b.file === f) {
                const keys = b.keys.split("+").map(k => k.trim()).filter(k => k)
                const exec = b.dsp === "exec_cmd" ? String(b.args[0] ?? "") : ""
                items.push({ id: "h" + b.line + "b" + items.length, kind: "bind", keys: Keybinds.parseCombo(keys.join(" ")) ?? keys,
                             title: b.description ?? "", cmd: exec,
                             rawHypr: exec ? "" : "hl.dsp." + b.dsp + "(" + (b.args ?? []).map(x => Syntax.lua(x)).join(", ") + ")",
                             opts: Array.isArray(b.opts) ? {} : (b.opts ?? {}), enabled: true, line: b.line - 1,
                             label: b.keys + "  →  " + (b.description || exec || b.dsp) })
            }
            // a line making several items (a loop) can't be commented out alone
            const perLine = {}
            for (const it of items) perLine[it.line] = (perLine[it.line] ?? 0) + 1
            for (const it of items) it.shared = perLine[it.line] > 1
            const rules = (d.rules ?? []).filter(r => r.file === f)
            const counts = {}
            for (const r of rules) counts[r.kind] = (counts[r.kind] ?? 0) + 1
            page.hypr = { items: items, other: Object.keys(counts).map(k => counts[k] + " × " + k), text: "", found: d.binds !== undefined }
            hyprText.reload()
        }
    }
    FileView {
        id: hyprText
        path: page.hyprFile
        printErrors: false
        onLoaded: page.hypr = Object.assign({}, page.hypr, { text: text(), found: true })
        onLoadFailed: page.hypr = Object.assign({}, page.hypr, { found: false })
    }

    // ── Importing ───────────────────────────────────────────────────────────
    function isPicked(it) { return picked[it.id] ?? !alreadyIn(it) }
    function setPicked(it, v) { const p = Object.assign({}, picked); p[it.id] = v; picked = p }

    // already in the settings (imported before)
    function alreadyIn(it) {
        if (it.kind === "autostart") return (Settings.autostart.items ?? []).some(a => a.cmd === it.cmd)
        const n = Keybinds.normKeys(it.keys)
        return (Settings.keybinds.binds ?? []).some(b => b.kind !== "disable" && Keybinds.normKeys(b.keys) === n)
    }

    function importFrom(src, wm) {
        const chosen = src.items.filter(it => isPicked(it) && !alreadyIn(it))
        if (chosen.length === 0) return
        const auto = (Settings.autostart.items ?? []).slice()
        const binds = (Settings.keybinds.binds ?? []).slice()
        let n = 0
        for (const it of chosen) {
            const id = "i" + Date.now() + (n++)
            if (it.kind === "autostart") {
                auto.push({ id: id, name: it.cmd.split(" ")[0].replace(/.*\//, ""), cmd: it.cmd, enabled: it.enabled, on: wm })
            } else if (it.cmd) {
                binds.push({ id: id, kind: "command", source: "command", keys: it.keys, name: it.title, cmd: it.cmd, on: wm, enabled: it.enabled })
            } else {
                binds.push({ id: id, kind: "original", keys: it.keys, name: it.title,
                             raw: wm === "niri" ? { niri: it.raw } : { hypr: it.rawHypr },
                             props: it.props ?? "", opts: it.opts ?? {}, on: wm, enabled: it.enabled })
            }
        }
        Settings.set("autostart", "items", auto)
        Settings.set("keybinds", "binds", binds)

        // comment out the imported (active, own-line) lines in the file
        if (commentOut) {
            const lines = src.text.split("\n")
            const mark = wm === "niri" ? "// (moved to the Quickshell settings) " : "-- (moved to the Quickshell settings) "
            let changed = false
            for (const it of chosen) {
                if (!it.enabled || it.shared || lines[it.line] === undefined) continue
                lines[it.line] = lines[it.line].replace(/^(\s*)/, "$1" + mark)
                changed = true
            }
            if (changed) {
                const file = wm === "niri" ? niriFile : hyprFile
                writer.command = ["sh", "-c",
                    'mkdir -p "$3" && cp -f "$2" "$3/$(basename "$2").$(date +%Y%m%d-%H%M%S)" && printf "%s" "$1" > "$2"',
                    "sh", lines.join("\n"), file, backupDir]
                writer.running = true
            }
        }
        Network.say("Imported " + chosen.length + (chosen.length === 1 ? " item" : " items") + " from " + (wm === "niri" ? "custom.kdl" : "custom.lua"))
        picked = {}
    }

    Process {
        id: writer
        onExited: page.reload()
    }

    // ── Deleting a custom file (and the line that loads it) ─────────────────
    // the main config without the lines that load the custom file
    function withoutInclude(text, wm) {
        if (wm === "niri") {
            return text.split("\n").filter((l, i, all) =>
                !(/^\s*include\b.*custom\/niri\/custom\.kdl/.test(l))
                && !(/^\s*\/\/ per-device extras/.test(l) && /custom\/niri\/custom\.kdl/.test(all[i + 1] ?? ""))).join("\n")
        }
        // the "only if it exists" block, or a plain dofile line
        return text.replace(/-- per-device extras[^\n]*\nlocal custom = [^\n]*custom\/hyprland\/custom\.lua"\nlocal cf = io\.open\(custom\)\nif cf then cf:close\(\); dofile\(custom\) end\n?/, "")
            .split("\n").filter(l => !/^\s*[^-\s].*custom\/hyprland\/custom\.lua/.test(l)).join("\n")
    }

    // sh: $1 custom file, $2 main config, $3 new main config text, $4 backup dir, $5 niri|hyprland
    // backs both up, checks the new config in place (includes are relative to
    // it), writes it, then deletes the custom file; nothing changes if the check fails
    readonly property string deleteScript:
        'mkdir -p "$4" || exit 1; ts=$(date +%Y%m%d-%H%M%S)\n'
        + '[ -f "$1" ] && cp -f "$1" "$4/$(basename "$1").$ts"\n'
        + 'cp -f "$2" "$4/$(basename "$2").$ts" || exit 1\n'
        + 'dir=$(dirname "$2")\n'
        + 'if [ "$5" = niri ]; then tmp=$(mktemp -p "$dir" .qs-check.XXXXXX.kdl); else tmp=$(mktemp -p "$dir" .qs-check.XXXXXX.lua); fi || exit 1\n'
        + 'printf "%s" "$3" > "$tmp"\n'
        + 'if [ "$5" = niri ]; then out=$(niri validate -c "$tmp" 2>&1); ok=$?\n'
        + 'else out=$(HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 Hyprland --verify-config -c "$tmp" 2>&1); ok=$?; fi\n'
        + 'if [ $ok -ne 0 ]; then rm -f "$tmp"; printf "%s\\n" "$out" | sed "s/\\x1b\\[[0-9;]*m//g" | grep -vE " (DEBUG|INFO) " | tail -5 >&2; exit 1; fi\n'
        + 'cat "$tmp" > "$2"; rm -f "$tmp"\n'
        + 'rm -f "$1"'

    function deleteCustom(wm) {
        const file = wm === "niri" ? niriFile : hyprFile
        const main = wm === "niri" ? NiriSettings.mainConfig : HyprSettings.mainConfig
        const text = (wm === "niri" ? NiriSettings : HyprSettings).readFile(main)
        if (text === "") { Network.say("Couldn't read " + main, true); return }
        deleter.wm = wm
        deleter.command = ["sh", "-c", deleteScript, "sh", file, main, withoutInclude(text, wm), backupDir, wm]
        deleter.running = true
    }

    Process {
        id: deleter
        property string wm: ""
        stderr: StdioCollector { id: delErr }
        onExited: code => {
            const name = deleter.wm === "niri" ? "custom.kdl" : "custom.lua"
            Network.say(code === 0 ? "Deleted " + name + " and the line loading it (backups in ~/.local/state/quickshell/custom-backups)"
                                   : "Nothing changed, the config didn't validate without it: " + delErr.text.trim(), code !== 0)
            page.reload()
        }
    }

    // ── UI ──────────────────────────────────────────────────────────────────
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: "Moves autostart entries and keybinds from your per-device custom configs into the settings, where they can be switched on / off "
              + "and are part of an export. Commented-out lines come in switched off."
        color: Colors.fade(0.5)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.WordWrap
    }

    NetCard {
        Layout.fillWidth: true
        title: "Options"
        NetRow {
            first: true
            label: "Comment out what's imported"
            desc: "In the custom file, so nothing starts twice. A backup goes to ~/.local/state/quickshell/custom-backups"
            ToggleSwitch { checked: page.commentOut; onToggled: v => page.commentOut = v }
        }
    }

    component Source: NetCard {
        id: srcCard
        required property var src
        required property string wm
        required property string file
        Layout.fillWidth: true
        icon: "󰋺"
        title: file.replace(page.home, "~")
        header: [
            ActionButton {
                id: delBtn
                visible: srcCard.src.found
                property bool armed: false
                icon: "󰆴"
                text: armed ? "Click again: delete file + include" : "Delete file"
                textColor: Colors.red
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return }
                    armed = false
                    page.deleteCustom(srcCard.wm)
                }
                Timer { id: disarm; interval: 4000; onTriggered: delBtn.armed = false }
            },
            ActionButton {
                icon: "󰋺"
                text: "Import selected"
                primary: true
                interactive: srcCard.src.items.some(it => page.isPicked(it) && !page.alreadyIn(it))
                onClicked: page.importFrom(srcCard.src, srcCard.wm)
            }
        ]

        Text {
            Layout.margins: 16
            visible: !srcCard.src.found || srcCard.src.items.length === 0
            text: !srcCard.src.found ? "No file here." : "Nothing to import (no autostart or keybinds)."
            color: Colors.fade(0.45)
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }
        Repeater {
            model: srcCard.src.items
            NetRow {
                required property var modelData
                required property int index
                readonly property var it: modelData
                readonly property bool done: page.alreadyIn(it)
                first: index === 0
                opacity: done ? 0.5 : 1
                label: (it.kind === "autostart" ? "󰐊  " : "󰌌  ") + it.label
                desc: (it.kind === "autostart" ? "Autostart" : "Keybind") + "  ·  line " + (it.line + 1)
                      + (it.enabled ? "" : "  ·  commented out → comes in switched off")
                      + (it.shared ? "  ·  made in a loop, stays in the file too" : "")
                      + (done ? "  ·  already in the settings" : "")
                ToggleSwitch {
                    visible: !done
                    checked: page.isPicked(it)
                    onToggled: v => page.setPicked(it, v)
                }
            }
        }
        NetRow {
            visible: srcCard.src.found
            label: "Done importing?"
            desc: "Delete file removes the line that loads it from " + (srcCard.wm === "niri" ? "config.kdl" : "hyprland.lua")
                  + " and deletes the file. Anything not imported (e.g. rules) goes with it; both files are backed up first."
        }
        NetRow {
            visible: srcCard.src.other.length > 0
            label: "Stays in the file"
            desc: srcCard.src.other.join(", ") + " (not part of the settings)"
        }
    }

    Source { src: page.niri; wm: "niri"; file: page.niriFile }
    Source { src: page.hypr; wm: "hyprland"; file: page.hyprFile }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        ActionButton { icon: "󰑓"; text: "Re-read files"; onClicked: page.reload() }
    }
}
