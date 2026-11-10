import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Default apps page (services/DefaultApps.qml): one app per category, from
// the installed apps that say they can open it.
ColumnLayout {
    id: page
    spacing: Tokens.space.s16

    Component.onCompleted: DefaultApps.refresh()

    Section {
        Layout.fillWidth: true
        title: "Open with"
        header: ActionButton { icon: "󰑓"; text: DefaultApps.loading ? "Loading…" : "Reload"; onClicked: DefaultApps.refresh() }
        SettingRow { first: true; visible: DefaultApps.error !== ""; label: "Problem"; desc: DefaultApps.error }
        Repeater {
            model: DefaultApps.categories
            SettingRow {
                required property var modelData
                required property int index
                readonly property var apps: DefaultApps.candidates[modelData.id] ?? []
                readonly property string cur: DefaultApps.current[modelData.id] ?? ""
                first: index === 0 && DefaultApps.error === ""
                label: modelData.icon + "  " + modelData.name
                desc: apps.length === 0 ? (DefaultApps.loading ? "…" : "no installed app opens these")
                      : (cur === "" ? "not set" : cur) + "  ·  " + (modelData.file ? modelData.file
                        : modelData.types.length + (modelData.types.length === 1 ? " type" : " types"))
                Dropdown {
                    visible: apps.length > 0
                    options: (cur === "" ? [{ label: "— not set —", value: "" }] : [])
                             .concat(apps.map(a => ({ label: DefaultApps.name(a), value: a, hint: a })))
                    value: cur
                    onEdited: v => { if (v !== "") DefaultApps.set(modelData.id, v) }
                }
            }
        }
    }
    Section {
        Layout.fillWidth: true
        title: "Note"
        SettingRow {
            first: true
            wide: true
            label: "Written to ~/.config/mimeapps.list"
            desc: "with xdg-mime, for every type of the category (e.g. Web browser = http, https, html, xhtml). The old file is copied to ~/.local/state/quickshell/backups first. Apps that ignore mimeapps.list (some Flatpaks, Electron apps) may still ask."
        }
        SettingRow {
            wide: true
            label: "Terminal: ~/.config/xdg-terminals.list"
            desc: "the xdg-terminal-exec standard (a desktop's own list, e.g. hyprland-xdg-terminals.list, wins on that desktop). The chosen app goes first, the old file is backed up the same way. Used by: Servers (SSH sessions)."
        }
    }
}
