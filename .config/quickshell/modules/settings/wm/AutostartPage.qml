import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Autostart page: programs started at login, written into the compositor
// override files (niri: spawn-sh-at-startup, Hyprland: hl.on("hyprland.start")
// — see the Syntax page). Each can be for both compositors or just one.
// What your own config starts is listed below, read-only.
ColumnLayout {
    id: page
    spacing: Tokens.space.s16

    readonly property var items: Settings.autostart.items ?? []
    readonly property string wm: Compositor.isHyprland ? "hyprland" : "niri"
    property string expanded: ""           // id of the entry being edited

    function save(list) { Settings.set("autostart", "items", list) }
    function update(id, patch) { save(items.map(a => a.id === id ? Object.assign({}, a, patch) : a)) }
    function remove(id) { save(items.filter(a => a.id !== id)) }

    // ── Add ─────────────────────────────────────────────────────────────────
    Section {
        id: addCard
        Layout.fillWidth: true
        title: "Add a program"
        icon: "󰐕"
        property string kind: "app"
        property string cmd: ""
        property string name: ""

        SettingRow {
            first: true
            wide: true
            label: "What to start"
            Segmented {
                options: [{ label: "App", value: "app", icon: "󰀻" }, { label: "Command", value: "command", icon: "󰆍" }]
                value: addCard.kind
                onEdited: v => { addCard.kind = v; addCard.cmd = ""; addCard.name = "" }
            }
        }
        SettingRow {
            visible: addCard.kind === "app"
            label: "App"
            // search + full list
            AppPicker {
                implicitWidth: 300
                value: addCard.cmd
                onPicked: (v, name) => { addCard.cmd = v; addCard.name = name }
            }
        }
        SettingRow {
            visible: addCard.kind === "command"
            label: "Command"
            desc: "Runs through sh, so pipes and && work"
            SearchField {
                implicitWidth: 300
                implicitHeight: Properties.buttonHeight
                icon: "󰆍"
                placeholderText: "e.g. nm-applet --indicator"
                text: addCard.cmd
                onTextEdited: addCard.cmd = text
            }
        }
        SettingRow {
            label: "Name"
            desc: "Shown in this list"
            SearchField {
                implicitWidth: 300
                implicitHeight: Properties.buttonHeight
                icon: ""
                placeholderText: addCard.cmd.split(" ")[0].replace(/.*\//, "") || "optional"
                text: addCard.name
                onTextEdited: addCard.name = text
            }
        }
        SettingRow {
            ActionButton {
                icon: "󰐕"
                text: "Add"
                primary: true
                interactive: addCard.cmd.trim() !== ""
                onClicked: {
                    const cmd = addCard.cmd.trim()
                    page.save(page.items.concat([{ id: "a" + Date.now(), name: addCard.name.trim() || cmd.split(" ")[0].replace(/.*\//, ""),
                                                   cmd: cmd, enabled: true, on: "both" }]))
                    addCard.cmd = ""; addCard.name = ""
                }
            }
        }
    }

    // ── Started by the shell ────────────────────────────────────────────────
    Section {
        Layout.fillWidth: true
        title: "Started at login" + (page.items.length > 0 ? "  ·  " + page.items.length : "")
        icon: "󰐊"

        Text {
            Layout.margins: Tokens.space.s16
            visible: page.items.length === 0
            text: "Nothing added yet."
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }

        Repeater {
            model: page.items
            ColumnLayout {
                id: entry
                required property var modelData
                required property int index
                readonly property var a: modelData
                readonly property bool open: page.expanded === a.id
                Layout.fillWidth: true
                spacing: 0

                SettingRow {
                    first: entry.index === 0
                    label: entry.a.name
                    desc: entry.a.cmd
                    opacity: entry.a.enabled === false ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: Anim.normal } }
                    Segmented {
                        small: true
                        options: [{ label: "Both", value: "both" }, { label: "niri", value: "niri" }, { label: "Hyprland", value: "hyprland" }]
                        value: entry.a.on ?? "both"
                        onEdited: v => page.update(entry.a.id, { on: v })
                    }
                    IconButton {
                        icon: "󰐊"
                        tooltip: "Run now"
                        onClicked: Quickshell.execDetached(["sh", "-c", entry.a.cmd])
                    }
                    IconButton {
                        icon: "󰏫"
                        tooltip: "Edit"
                        active: entry.open
                        onClicked: page.expanded = entry.open ? "" : entry.a.id
                    }
                    IconButton {
                        id: del
                        ConfirmArm { id: delArm }
                        readonly property bool armed: delArm.armed !== ""
                        icon: "󰆴"
                        tooltip: armed ? "Click again to remove" : "Remove"
                        active: armed
                        textColor: Colors.red
                        onClicked: if (delArm.confirm("remove")) page.remove(entry.a.id)
                    }
                    ToggleSwitch {
                        checked: entry.a.enabled !== false
                        onToggled: v => page.update(entry.a.id, { enabled: v })
                    }
                }
                Reveal {
                    open: entry.open
                    SettingRow {
                        sub: true
                        label: "Name"
                        SearchField {
                            implicitWidth: 300
                            implicitHeight: Properties.buttonHeight
                            icon: ""
                            text: entry.a.name
                            onEditingFinished: if (text.trim() !== "" && text !== entry.a.name) page.update(entry.a.id, { name: text.trim() })
                        }
                    }
                    SettingRow {
                        sub: true
                        label: "Command"
                        SearchField {
                            implicitWidth: 300
                            implicitHeight: Properties.buttonHeight
                            icon: "󰆍"
                            text: entry.a.cmd
                            onEditingFinished: if (text.trim() !== "" && text !== entry.a.cmd) page.update(entry.a.id, { cmd: text.trim() })
                        }
                    }
                }
            }
        }
    }

    // ── From the config ─────────────────────────────────────────────────────
    Section {
        Layout.fillWidth: true
        title: "From your " + (Compositor.name || "niri") + " config  ·  read-only"
        icon: "󰈙"
        Text {
            Layout.margins: Tokens.space.s16
            visible: Keybinds.autostart.length === 0
            text: "Your config doesn't start anything."
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }
        Repeater {
            model: Keybinds.autostart
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.cmd
                desc: (modelData.file ?? "").replace(Quickshell.env("HOME"), "~")
            }
        }
    }

    Text {
        Layout.leftMargin: Tokens.space.s6
        Layout.fillWidth: true
        text: "Added programs start at your next login (niri: spawn-sh-at-startup, Hyprland: hl.on(\"hyprland.start\")). Edit the read-only ones in the file shown under them."
        color: Colors.fade(0.4)
        font.pixelSize: Tokens.font.caption
        font.family: Properties.fontFamily
        wrapMode: Text.WordWrap
    }

    Component.onCompleted: Keybinds.refresh()
}
