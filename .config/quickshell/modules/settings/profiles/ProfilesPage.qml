import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Settings profiles (services/SettingsProfiles.qml): save chosen settings
// groups under a name, switch between profiles (also: the icons at the bottom
// of the sidebar), undo the last switch, export / import profiles.
ColumnLayout {
    id: page
    spacing: 16

    property string newName: ""
    property var picked: SettingsProfiles.defaultGroups()
    property bool withColors: true
    property string msg: ""
    ConfirmArm { id: deleteArm }
    readonly property alias confirmDelete: deleteArm.armed     // the profile waiting for its second click
    property string iconFor: ""                // profile whose icon picker is open
    property var importList: []                 // SettingsProfiles.readImport(), waiting for Import

    // ── Export / import (zenity picks the files) ──
    function exportProfiles(names) {
        const def = Quickshell.env("HOME") + "/" + (names.length === 1 ? names[0].replace(/ /g, "-") + "-profile" : "quickshell-profiles") + ".json"
        Jobs.run(["zenity", "--file-selection", "--save", "--title=Export profiles", "--filename=" + def,
                  "--file-filter=JSON | *.json", "--file-filter=All files | *"], (code, out) => {
            if (code === 0 && out.trim() !== "") SettingsProfiles.exportTo(out.trim(), names, (ok, m) => page.msg = m)
            else if (code !== 1) page.msg = code === 127 ? "zenity isn't installed" : "couldn't open the file picker"
        })
    }
    function pickImport() {
        Jobs.run(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Import profiles",
                  "--filename=" + Quickshell.env("HOME") + "/", "--file-filter=JSON | *.json", "--file-filter=All files | *"], (code, out) => {
            const paths = out.split("\n").filter(x => x.trim() !== "")
            if (code === 0 && paths.length > 0) page.importList = SettingsProfiles.readImport(paths)
            else if (code !== 1) page.msg = code === 127 ? "zenity isn't installed" : "couldn't open the file picker"
        })
    }

    Component.onCompleted: SettingsProfiles.refresh()

    NetCard {
        Layout.fillWidth: true
        title: "Profiles"
        header: [
            ActionButton {
                icon: "󰕌"; text: "Undo last switch"
                interactive: SettingsProfiles.hasUndo
                onClicked: SettingsProfiles.undo(ok => page.msg = ok ? "restored" : "nothing to undo")
            },
            ActionButton {
                icon: "󰈝"; text: "Export all"
                interactive: SettingsProfiles.profiles.some(p => !p.broken)
                onClicked: page.exportProfiles(SettingsProfiles.profiles.filter(p => !p.broken).map(p => p.name))
            },
            ActionButton { icon: "󰋺"; text: "Import…"; onClicked: page.pickImport() }
        ]
        NetRow {
            id: importRow
            first: true
            visible: page.importList.length > 0
            wide: true
            readonly property int good: page.importList.filter(e => e.problem === "").length
            label: good + (good === 1 ? " profile" : " profiles") + " to import"
                   + (good < page.importList.length ? "  ·  " + (page.importList.length - good) + " can't be imported" : "")
            desc: page.importList.map(e => (e.problem !== "" ? "󰀦 " + e.name + " (" + e.file + "): " + e.problem
                                                             : "󰄬 " + e.name + (e.exists ? "  (replaces yours)" : ""))).join("\n")
            RowLayout {
                spacing: 6
                Item { Layout.fillWidth: true }
                ActionButton { text: "Cancel"; onClicked: page.importList = [] }
                ActionButton {
                    icon: "󰋺"; text: "Import " + importRow.good; primary: true
                    interactive: importRow.good > 0
                    onClicked: SettingsProfiles.importProfiles(page.importList, n => { page.msg = n + (n === 1 ? " profile" : " profiles") + " imported"; page.importList = [] })
                }
            }
        }
        NetRow {
            first: page.importList.length === 0
            visible: SettingsProfiles.profiles.length === 0
            label: "No profiles yet"
            desc: "save the current settings below, change things, save another one, then switch here (or qs ipc call profiles apply <name>)"
        }
        NetRow {
            visible: SettingsProfiles.error !== "" || page.msg !== ""
            label: SettingsProfiles.error !== "" ? "Not applied" : page.msg
            desc: SettingsProfiles.error
        }
        Repeater {
            model: SettingsProfiles.profiles
            NetRow {
                required property var modelData
                required property int index
                readonly property var p: modelData
                first: index === 0 && SettingsProfiles.error === "" && page.msg === "" && page.importList.length === 0
                wide: true
                label: p.name + (p.name === SettingsProfiles.active ? "  ·  active" : "")
                desc: p.broken ? "󰀦 not valid JSON" : p.groups.map(g => Settings.groupLabel(g)).join(", ") + (p.hasColors ? " + colors" : "")
                      + (p.saved ? "  ·  saved " + p.saved.slice(0, 16).replace("T", " ") : "")
                ColumnLayout {
                  spacing: 8
                  RowLayout {
                    spacing: 6
                    IconButton {
                        icon: p.icon || p.name.charAt(0).toUpperCase()
                        active: page.iconFor === p.name
                        tooltip: "Icon in the switcher at the bottom of the sidebar"
                        interactive: !p.broken
                        onClicked: page.iconFor = page.iconFor === p.name ? "" : p.name
                    }
                    Item { Layout.fillWidth: true }
                    ActionButton {
                        icon: "󰄬"; text: "Apply"; primary: p.name !== SettingsProfiles.active
                        interactive: !p.broken
                        onClicked: SettingsProfiles.apply(p.name, (ok, m) => page.msg = ok ? "“" + p.name + "” applied" : "")
                    }
                    ActionButton {
                        icon: "󰆓"; text: "Update"
                        onClicked: SettingsProfiles.save(p.name, p.groups, p.hasColors, (ok, m) => page.msg = ok ? "“" + p.name + "” updated with the current settings" : m)
                    }
                    IconButton {
                        icon: "󰈝"
                        tooltip: "Export this profile"
                        interactive: !p.broken
                        onClicked: page.exportProfiles([p.name])
                    }
                    IconButton {
                        icon: page.confirmDelete === p.name ? "󰄬" : "󰆴"
                        textColor: page.confirmDelete === p.name ? Colors.red : Icons.tint(icon, Properties.color)
                        tooltip: page.confirmDelete === p.name ? "Click again to delete" : "Delete"
                        onClicked: {
                            if (deleteArm.confirm(p.name)) SettingsProfiles.remove(p.name)
                        }
                    }
                  }
                  // icon picker
                  Flow {
                    Layout.fillWidth: true
                    visible: page.iconFor === p.name
                    spacing: 6
                    Repeater {
                        model: [""].concat(SettingsProfiles.iconChoices)
                        IconButton {
                            required property string modelData
                            icon: modelData || p.name.charAt(0).toUpperCase()
                            tooltip: modelData ? "" : "The first letter"
                            active: (p.icon ?? "") === modelData
                            onClicked: { SettingsProfiles.setIcon(p.name, modelData); page.iconFor = "" }
                        }
                    }
                  }
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Save the current settings as a profile"
        NetRow {
            first: true
            label: "Name"
            desc: SettingsProfiles.profiles.some(p => p.name === page.newName.trim()) ? "exists: saving replaces it" : "e.g. Work, Gaming, Presentation"
            RowLayout {
                spacing: 8
                SearchField {
                    Layout.preferredWidth: 200
                    icon: ""; clearable: false
                    text: page.newName
                    onTextEdited: page.newName = text
                }
                ActionButton {
                    icon: "󰆓"; text: "Save"; primary: true
                    interactive: page.picked.length > 0
                    onClicked: SettingsProfiles.save(page.newName, page.picked, page.withColors, (ok, m) => { page.msg = ok ? "saved" : m; if (ok) page.newName = "" })
                }
            }
        }
        NetRow {
            wide: true
            label: "What it contains"
            desc: "machine-specific groups (monitors, connections, dotfiles, …) are off by default"
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Settings.groups
                    Chip {
                        required property string modelData
                        readonly property bool on: page.picked.includes(modelData)
                        text: (on ? "󰄬 " : "") + (Settings.groupLabel(modelData))
                        copyable: false
                        accent: on
                        opacity: Object.keys(Settings[modelData] ?? {}).length > 0 || on ? 1 : 0.45
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.picked = parent.on ? page.picked.filter(g => g !== parent.modelData) : page.picked.concat([parent.modelData])
                        }
                    }
                }
            }
        }
        NetRow {
            label: "Include the pywal colors"
            desc: "applying the profile then also applies its colors (Theme → Undo works too)"
            ToggleSwitch { checked: page.withColors; onToggled: v => page.withColors = v }
        }
    }
}
