import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"
import "../../keybinds"

// Keybinds page: search (by what a bind does, or by keys: "super shift s"),
// record a combo, edit / disable any bind, and make new ones.
// Your config files are never touched: changes go into the shell's override
// file, which is loaded last (Settings.keybinds.binds → NiriSettings /
// HyprSettings, syntax from the Syntax page):
//   kind "command"   a new bind that runs a command (app, shell action, …)
//   kind "original"  a bind from your config under other keys / a new name
//   kind "disable"   a bind from your config switched off
ColumnLayout {
    id: page
    spacing: 16

    property string focusKeys: ""          // from the launcher's cheatsheet: open this bind's editor
    signal focusConsumed()

    readonly property string wm: Compositor.isHyprland ? "hyprland" : "niri"
    readonly property var entries: Settings.keybinds.binds ?? []
    property string query: ""
    property var editing: null              // { item (raw bind) | null, entry (settings entry) | null }

    function saveEntries(list) { Settings.set("keybinds", "binds", list) }

    Component.onCompleted: { Keybinds.refresh(); focusTimer.restart() }
    onFocusKeysChanged: focusTimer.restart()
    // after Keybinds has (re)read the binds
    Timer {
        id: focusTimer
        interval: 400
        onTriggered: {
            if (page.focusKeys === "") return
            const b = Keybinds.all.find(x => Keybinds.normKeys(x.keys) === page.focusKeys)
            if (b) page.startEdit(b)
            page.focusConsumed()
        }
    }

    // ── Search ──────────────────────────────────────────────────────────────
    readonly property var combo: Keybinds.parseCombo(query)
    readonly property var comboBind: combo ? Keybinds.bindFor(combo) : null

    function rowMatches(r) {
        if (combo) {
            const n = Keybinds.normKeys(combo)
            return r.items.some(b => Keybinds.normKeys(b.keys) === n)
        }
        const q = query.trim().toLowerCase()
        return q === "" || (r.desc + " " + r.category + " " + r.combos.map(c => c.map(k => Keybinds.keyLabel(k)).join(" ")).join(" "))
            .toLowerCase().includes(q)
    }

    readonly property var groups: Keybinds.categories.map(c => ({
        name: c.name, icon: c.icon,
        rows: Keybinds.binds.filter(r => r.category === c.name && page.rowMatches(r))
    })).filter(g => g.rows.length > 0)

    // ── Editing ─────────────────────────────────────────────────────────────
    function isShellMade(b) { return b && Keybinds.isShellFile(b.file) }
    // the settings entry behind a bind the shell wrote
    function entryFor(b) {
        const n = Keybinds.normKeys(b.keys)
        return entries.find(e => e.kind !== "disable" && Keybinds.normKeys(e.keys) === n) ?? null
    }

    function startEdit(b) {
        editing = { item: b, entry: isShellMade(b) ? entryFor(b) : null }
        editor.load()
    }
    function startNew(keys) {
        editing = { item: null, entry: null }
        editor.load()
        if (keys) editor.keys = keys
    }
    function editEntry(e) {
        editing = { item: null, entry: e }
        editor.load()
    }

    // ── Toolbar ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SearchField {
            id: search
            Layout.fillWidth: true
            placeholderText: "Search by action or keys (\"close\", \"super shift s\")"
            text: page.query
            onTextChanged: page.query = text
        }
        KeyRecorder {
            onRecorded: keys => search.text = keys.join("+")
        }
        ActionButton {
            icon: "󰐕"
            text: "New keybind"
            primary: true
            onClicked: page.startNew(page.combo && !page.comboBind ? page.combo : null)
        }
    }

    // what a searched / recorded combo does
    Reveal {
        open: page.combo !== null && page.editing === null
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: comboRow.implicitHeight + 18
            radius: 12
            readonly property color tint: page.comboBind ? Qt.rgba(1, 1, 1, 1) : Colors.color6
            color: Qt.rgba(tint.r, tint.g, tint.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.3)
            RowLayout {
                id: comboRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 9 }
                spacing: 8
                Repeater {
                    model: page.combo ?? []
                    Keycap { required property string modelData; key: modelData }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: page.comboBind ? "→  " + Keybinds.describe(page.comboBind) : "is free"
                    color: "white"
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                ActionButton {
                    icon: page.comboBind ? "󰏫" : "󰐕"
                    text: page.comboBind ? "Edit" : "Create keybind"
                    primary: !page.comboBind
                    onClicked: page.comboBind ? page.startEdit(page.comboBind) : page.startNew(page.combo)
                }
            }
        }
    }

    // ── Editor ──────────────────────────────────────────────────────────────
    Reveal {
        open: page.editing !== null
        NetCard {
            id: editor
            Layout.fillWidth: true
            readonly property var item: page.editing?.item ?? null
            readonly property var entry: page.editing?.entry ?? null
            // editing a bind from your config (its action stays)
            readonly property bool fromConfig: item !== null && entry === null
            readonly property bool isNew: item === null && entry === null
            title: isNew ? "New keybind" : "Edit keybind"
            icon: isNew ? "󰐕" : "󰏫"
            tint: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.06)

            property var keys: []
            property string keysText: ""
            property string name: ""
            property string source: "app"       // app | command | shell
            property string cmd: ""
            property string on: "both"
            property bool replaceOk: false       // "Replace it" clicked for a taken combo

            function load() {
                replaceOk = false
                const e = entry, b = item
                keys = (e?.keys ?? b?.keys ?? []).slice()
                keysText = keys.join("+")
                name = e?.name ?? (b ? (b.title || Keybinds.describe(b)) : "")
                source = e?.source ?? "command"
                if (!e && !b) source = "app"
                cmd = e?.cmd ?? ""
                on = e?.on ?? (fromConfig ? page.wm : "both")
            }

            readonly property var other: keys.length > 0 ? Keybinds.bindFor(keys) : null
            readonly property bool replacesOther: other !== null && !(item && Keybinds.normKeys(other.keys) === Keybinds.normKeys(item.keys))
            readonly property bool conflict: replacesOther && !replaceOk
            readonly property string problem: keys.length === 0 ? "Pick keys: record them or type e.g. Mod+Shift+Y"
                : Keybinds.normKeys(keys) === "mod+s" ? "Mod+S opens the settings (the shell's own bind)"
                : conflict ? "Already used by: " + Keybinds.describe(other)
                : (fromConfig || entry?.kind === "original") ? ""
                : cmd.trim() === "" ? (source === "app" ? "Pick an app" : source === "shell" ? "Pick an action" : "Type a command")
                : ""

            NetRow {
                first: true
                wide: true
                label: "Keys"
                desc: editor.replacesOther ? (editor.replaceOk ? "Replaces: " : "󰀦 Already used by: ") + Keybinds.describe(editor.other)
                    : editor.keys.length > 0 ? "Free" : ""
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: editor.keys
                        Keycap { required property string modelData; key: modelData }
                    }
                    SearchField {
                        Layout.fillWidth: true
                        implicitHeight: Properties.buttonHeight
                        icon: ""
                        clearable: false
                        placeholderText: "Mod+Shift+Y"
                        text: editor.keysText
                        onTextEdited: { editor.keysText = text; editor.keys = Keybinds.parseCombo(text) ?? []; editor.replaceOk = false }
                    }
                    KeyRecorder { onRecorded: k => { editor.keys = k; editor.keysText = k.join("+"); editor.replaceOk = false } }
                }
            }
            NetRow {
                label: "Name"
                desc: "Shown in the cheatsheet / hotkey overlay"
                SearchField {
                    implicitWidth: 300
                    implicitHeight: Properties.buttonHeight
                    icon: ""
                    text: editor.name
                    onTextEdited: editor.name = text
                }
            }
            NetRow {
                visible: editor.fromConfig || editor.entry?.kind === "original"
                label: "Action"
                desc: "Stays as it is in your config"
                Text {
                    text: editor.item ? Keybinds.describe(editor.item) : (editor.entry?.desc ?? "")
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                }
            }
            NetRow {
                visible: !(editor.fromConfig || editor.entry?.kind === "original")
                wide: true
                label: "Action"
                Segmented {
                    options: [{ label: "Open app", value: "app", icon: "󰀻" }, { label: "Command", value: "command", icon: "󰆍" },
                              { label: "Shell", value: "shell", icon: "󰕮" }]
                    value: editor.source
                    onEdited: v => { editor.source = v; editor.cmd = "" }
                }
            }
            NetRow {
                sub: true
                visible: editor.source === "app" && !(editor.fromConfig || editor.entry?.kind === "original")
                label: "App"
                AppPicker {
                    implicitWidth: 300
                    value: editor.cmd
                    onPicked: (v, name) => { editor.cmd = v; if (editor.name === "") editor.name = "Open " + name }
                }
            }
            NetRow {
                sub: true
                visible: editor.source === "command" && !(editor.fromConfig || editor.entry?.kind === "original")
                label: "Command"
                desc: "Runs through sh"
                SearchField {
                    implicitWidth: 300
                    implicitHeight: Properties.buttonHeight
                    icon: "󰆍"
                    placeholderText: "e.g. kitty -e btop"
                    text: editor.cmd
                    onTextEdited: editor.cmd = text
                }
            }
            NetRow {
                sub: true
                visible: editor.source === "shell" && !(editor.fromConfig || editor.entry?.kind === "original")
                label: "Shell action"
                DropdownControl {
                    implicitWidth: 300
                    options: shellActions
                    value: editor.cmd
                    onEdited: v => { editor.cmd = v; if (editor.name === "") editor.name = shellActions.find(a => a.value === v)?.label ?? "" }
                }
            }
            NetRow {
                visible: !editor.fromConfig && editor.entry?.kind !== "original"
                label: "For"
                Segmented {
                    small: true
                    options: [{ label: "Both", value: "both" }, { label: "niri", value: "niri" }, { label: "Hyprland", value: "hyprland" }]
                    value: editor.on
                    onEdited: v => editor.on = v
                }
            }
            NetRow {
                Text {
                    Layout.fillWidth: true
                    text: editor.problem
                    color: editor.conflict ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 11
                    font.bold: editor.conflict
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    visible: editor.conflict
                    icon: "󰛔"
                    text: "Replace it"
                    textColor: "#f38ba8"
                    onClicked: editor.replaceOk = true
                }
                ActionButton {
                    visible: editor.fromConfig
                    icon: "󰂭"
                    text: "Disable"
                    textColor: "#f38ba8"
                    onClicked: { page.disable(editor.item); page.editing = null }
                }
                ActionButton {
                    visible: editor.entry !== null
                    icon: "󰆴"
                    text: editor.entry?.kind === "original" ? "Reset" : "Delete"
                    textColor: "#f38ba8"
                    onClicked: { page.removeEntry(editor.entry); page.editing = null }
                }
                ActionButton {
                    icon: "󰅖"
                    text: "Cancel"
                    onClicked: page.editing = null
                }
                ActionButton {
                    icon: "󰄬"
                    text: "Save"
                    primary: true
                    interactive: editor.problem === ""
                    onClicked: { page.save(); page.editing = null }
                }
            }
        }
    }

    // ── Saving ──────────────────────────────────────────────────────────────
    function newId() { return "k" + Date.now() + Math.floor(Math.random() * 1000) }

    function save() {
        const ed = editor
        let list = entries.slice()
        if (ed.entry) {
            // one of ours: change it in place
            list = list.map(e => e.id !== ed.entry.id ? e
                : Object.assign({}, e, { keys: ed.keys, name: ed.name.trim(),
                                         cmd: e.kind === "original" ? e.cmd : ed.cmd.trim(), source: e.kind === "original" ? e.source : ed.source,
                                         on: e.kind === "original" ? e.on : ed.on }))
        } else if (ed.item) {
            // from your config: re-create it here, and switch the old keys off if they changed
            const b = ed.item
            const from = Keybinds.normKeys(b.keys)
            const moved = Keybinds.normKeys(ed.keys) !== from
            list = list.filter(e => e.from !== from)
            if (moved) list.push({ id: newId(), kind: "disable", keys: b.keys, on: page.wm, from: from, desc: Keybinds.describe(b) })
            list.push({ id: newId(), kind: "original", keys: ed.keys, name: ed.name.trim(), raw: Keybinds.rawFor(b),
                        props: b.rawProps ?? "", opts: b.opts ?? {}, on: page.wm, from: from, desc: Keybinds.describe(b) })
        } else {
            list.push({ id: newId(), kind: "command", source: ed.source, keys: ed.keys, name: ed.name.trim(),
                        cmd: ed.cmd.trim(), on: ed.on, enabled: true })
        }
        saveEntries(list)
    }

    function disable(b) {
        const from = Keybinds.normKeys(b.keys)
        saveEntries(entries.filter(e => e.from !== from)
            .concat([{ id: newId(), kind: "disable", keys: b.keys, on: page.wm, from: from, desc: Keybinds.describe(b) }]))
    }

    // an "original" goes together with the "disable" of its old keys
    function removeEntry(e) {
        saveEntries(entries.filter(x => x.id !== e.id && !(e.from && x.from === e.from)))
    }

    // ── Apps and shell actions for new binds ────────────────────────────────
    readonly property var shellActions: [
        { label: "App launcher", value: "qs ipc call Launcher toggleAppSearch" },
        { label: "Clipboard history", value: "qs ipc call Launcher toggleClipboard" },
        { label: "Wallpaper picker", value: "qs ipc call Launcher toggleWallpapers" },
        { label: "Keybind cheatsheet", value: "qs ipc call Launcher toggleKeybinds" },
        { label: "Dashboard", value: "qs ipc call dashboard toggle" },
        { label: "Control center", value: "qs ipc call controlCenter toggle" },
        { label: "Settings", value: "qs ipc call settings toggle" },
        { label: "Calendar", value: "qs ipc call calendar toggle" },
        { label: "Lock screen", value: "qs ipc call lockscreen lock" },
        { label: "Dismiss latest notification", value: "qs ipc call notifs dismissLatest" }
    ]

    // ── Changed here ────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.entries.length > 0 && page.query === ""
        title: "Changed here  ·  " + page.entries.length
        icon: "󰏫"
        Repeater {
            model: page.entries
            NetRow {
                required property var modelData
                required property int index
                readonly property var e: modelData
                first: index === 0
                opacity: e.enabled === false ? 0.5 : 1
                label: e.kind === "disable" ? "Disabled: " + (e.desc ?? "")
                     : e.kind === "original" ? (e.name || e.desc || "")
                     : (e.name || e.cmd)
                desc: e.kind === "original" ? (e.from && Keybinds.normKeys(e.keys) !== e.from ? "Moved from " + e.from : "Renamed") + "  ·  " + (e.on ?? "both")
                    : e.kind === "disable" ? "Back with Restore  ·  " + (e.on ?? "both")
                    : e.cmd + "  ·  " + (e.on ?? "both")
                Repeater {
                    model: e.keys
                    Keycap { required property string modelData; key: modelData }
                }
                IconButton {
                    visible: e.kind !== "disable"
                    icon: "󰏫"
                    tooltip: "Edit"
                    onClicked: page.editEntry(e)
                }
                IconButton {
                    icon: e.kind === "command" ? "󰆴" : "󰑓"
                    tooltip: e.kind === "command" ? "Delete" : "Restore your config's bind"
                    textColor: e.kind === "command" ? "#f38ba8" : Properties.color
                    onClicked: page.removeEntry(e)
                }
                ToggleSwitch {
                    visible: e.kind === "command"
                    checked: e.enabled !== false
                    onToggled: v => page.saveEntries(page.entries.map(x => x.id === e.id ? Object.assign({}, x, { enabled: v }) : x))
                }
            }
        }
    }

    // ── All binds ───────────────────────────────────────────────────────────
    Text {
        Layout.leftMargin: 6
        text: Keybinds.error !== "" ? "󰀦  " + Keybinds.error
            : page.groups.reduce((n, g) => n + g.rows.length, 0) + " shown  ·  from your " + (Compositor.name || "niri") + " config"
        color: Keybinds.error !== "" ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 11
        font.family: Properties.fontFamily
    }

    Repeater {
        model: page.groups
        NetCard {
            required property var modelData
            readonly property var g: modelData
            Layout.fillWidth: true
            title: g.name + "  ·  " + g.rows.length
            icon: g.icon
            Repeater {
                model: g.rows
                NetRow {
                    required property var modelData
                    required property int index
                    readonly property var r: modelData
                    first: index === 0
                    label: r.desc
                    changed: r.items.some(b => page.isShellMade(b))
                    // each combo: its keys, click to edit that one
                    Repeater {
                        model: r.items
                        Rectangle {
                            required property var modelData
                            implicitWidth: capsRow.implicitWidth + 10
                            implicitHeight: 30
                            radius: 8
                            color: capMouse.containsMouse ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.15) : "transparent"
                            border.width: 1
                            border.color: capMouse.containsMouse ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            RowLayout {
                                id: capsRow
                                anchors.centerIn: parent
                                spacing: 3
                                Repeater {
                                    model: modelData.keys
                                    Keycap { required property string modelData; key: modelData; compact: true }
                                }
                            }
                            MouseArea {
                                id: capMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.startEdit(parent.modelData)
                            }
                        }
                    }
                    IconButton {
                        icon: "󰏫"
                        tooltip: "Edit"
                        onClicked: page.startEdit(r.items[0])
                    }
                }
            }
        }
    }
}
