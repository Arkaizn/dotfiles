import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Settings profiles (services/SettingsProfiles.qml): save chosen settings
// groups under a name, switch between profiles, undo the last switch.
ColumnLayout {
    id: page
    spacing: 16

    property string newName: ""
    property var picked: SettingsProfiles.defaultGroups()
    property bool withColors: true
    property string msg: ""
    property string confirmDelete: ""
    readonly property var names: ({ properties: "Appearance / bar / panels", niri: "niri", hyprland: "Hyprland", monitors: "Monitors",
        calendar: "Calendar", network: "Network page", battery: "Battery alerts", profile: "Profile", autostart: "Autostart",
        keybinds: "Keybinds", syntax: "Syntax", bar: "Bar layout", notifications: "Notifications", theme: "Theme", audio: "Audio",
        bluetooth: "Bluetooth", power: "Power", defaultApps: "Default apps", clipboard: "Clipboard", connections: "Connections",
        capture: "Screenshots", dotfiles: "Dotfiles", netTools: "Network tools", updates: "Updates", settingsProfiles: "Profiles",
        wizard: "First run", health: "Health", perfmon: "Performance monitor", launcher: "Launcher", icons: "Icons", monitorsPage: "Monitors page" })

    Component.onCompleted: SettingsProfiles.refresh()

    NetCard {
        Layout.fillWidth: true
        title: "Profiles"
        header: ActionButton {
            icon: "󰕌"; text: "Undo last switch"
            interactive: SettingsProfiles.hasUndo
            onClicked: SettingsProfiles.undo(ok => page.msg = ok ? "restored" : "nothing to undo")
        }
        NetRow {
            first: true
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
                first: index === 0 && SettingsProfiles.error === "" && page.msg === ""
                wide: true
                label: p.name + (p.name === SettingsProfiles.active ? "  ·  active" : "")
                desc: p.broken ? "󰀦 not valid JSON" : p.groups.map(g => page.names[g] ?? g).join(", ") + (p.hasColors ? " + colors" : "")
                      + (p.saved ? "  ·  saved " + p.saved.slice(0, 16).replace("T", " ") : "")
                RowLayout {
                    spacing: 6
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
                        icon: page.confirmDelete === p.name ? "󰄬" : "󰆴"
                        textColor: page.confirmDelete === p.name ? Colors.red : Properties.color
                        tooltip: page.confirmDelete === p.name ? "Click again to delete" : "Delete"
                        onClicked: {
                            if (page.confirmDelete === p.name) { SettingsProfiles.remove(p.name); page.confirmDelete = "" }
                            else { page.confirmDelete = p.name; delTimer.restart() }
                        }
                    }
                }
            }
        }
    }
    Timer { id: delTimer; interval: 3000; onTriggered: page.confirmDelete = "" }

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
                        text: (on ? "󰄬 " : "") + (page.names[modelData] ?? modelData)
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
