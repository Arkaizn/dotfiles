import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../settings/network"

// First-run setup: opens by itself on a new install (no settings.json when the
// shell started, Settings.fresh) until finished or skipped; again any time
// with `qs ipc call wizard open` or Settings → Maintenance → Health.
// Every choice applies right away (the real bar changes while you pick).
Scope {
    id: root

    property bool open: false
    property int step: 0
    readonly property var steps: ["Welcome", "You", "Bar", "Notifications", "Look & keys", "Done"]

    function show() { step = 0; open = true; Health.run() }
    function finish() { Settings.set("wizard", "done", true); open = false }

    Timer {
        running: Settings.loaded && Settings.fresh && !(Settings.wizard.done ?? false)
        interval: 2500
        onTriggered: root.show()
    }

    IpcHandler {
        target: "wizard"
        function open(): void { root.show() }
    }
    readonly property var api: ({ open: () => root.show() })     // Panels.open("wizard")
    Component.onCompleted: Panels.register("wizard", api)
    Component.onDestruction: Panels.unregister("wizard", api)

    // bar presets (BarLayout zones)
    readonly property var presets: [
        { id: "default", name: "Default", desc: "everything: workspaces, updates, dotfiles, tray, media, clock, devices", layout: BarLayout.defaultLayout },
        { id: "minimal", name: "Minimal", desc: "workspaces, clock, volume, network, notifications, power",
          layout: { left: ["arch", "workspaces"], centerLeft: [], center: ["clock"], centerRight: [], right: ["recording", "volume", "network", "notifs", "power"] } },
        { id: "stats", name: "With system stats", desc: "the default plus CPU, memory, GPU and temperature next to the clock",
          layout: { left: ["arch", "workspaces", "updater", "tray"], centerLeft: ["music"], center: ["clock"], centerRight: ["cpu", "cputemp", "mem", "gpu"],
                    right: ["recording", "bluetooth", "volume", "network", "notifs", "battery", "power"] } }
    ]

    LazyLoader {
        active: root.open
        FloatingWindow {
            id: win
            title: "Welcome"
            visible: true
            implicitWidth: 760
            implicitHeight: 600
            // opaque: nothing of the desktop (or the compositor's blur) shows through
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 1)
            onClosed: root.open = false

            // Ctrl +/−/0, Ctrl + wheel: the whole window bigger or smaller (AppZoom)
            ZoomArea {
                id: zoomArea
                app: "wizard"
                anchors.fill: parent
                ColumnLayout {
                    anchors { fill: parent; margins: 26 }
                    spacing: 18

                    // step dots
                    RowLayout {
                        spacing: 8
                        Repeater {
                            model: root.steps
                            RowLayout {
                                required property string modelData
                                required property int index
                                spacing: 6
                                Rectangle {
                                    implicitWidth: 22; implicitHeight: 22; radius: 11
                                    color: index <= root.step ? Colors.color6 : Colors.fade(0.1)
                                    Text { anchors.centerIn: parent; text: index < root.step ? "󰄬" : index + 1; color: index <= root.step ? "black" : Colors.ink; font.pixelSize: 11; font.family: Properties.fontFamily }
                                }
                                Text { text: modelData; color: index === root.step ? Colors.ink : Colors.fade(0.45); font.pixelSize: 12; font.family: Properties.fontFamily }
                            }
                        }
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.step

                        // ── 0 welcome ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "Welcome to your shell"; color: Colors.ink; font.pixelSize: 24; font.bold: true; font.family: Properties.fontFamily }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                text: "A few choices to get started; everything can be changed later in the settings app. First, a check of what the shell needs:"
                                color: Colors.fade(0.7); font.pixelSize: 13; font.family: Properties.fontFamily
                            }
                            NetCard {
                                Layout.fillWidth: true
                                NetRow {
                                    first: true
                                    label: Health.running ? "Checking…" : Health.errors > 0 ? Health.errors + " problem(s)" : Health.warnings > 0 ? "Works, " + Health.warnings + " warning(s)" : "Everything is there"
                                    desc: Health.results.filter(r => r.status === "error" || r.status === "warn").map(r => r.title + ": " + r.detail).join("\n") || "all checks ok"
                                }
                                Repeater {
                                    model: Health.results.filter(r => r.fix !== "" && (r.status === "error" || r.status === "warn"))
                                    NetRow {
                                        required property var modelData
                                        wide: true
                                        label: "Fix: " + modelData.title
                                        desc: modelData.fix
                                        ActionButton { icon: "󰆏"; text: "Copy"; onClicked: Quickshell.execDetached(["wl-copy", "--", modelData.fix]) }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // ── 1 you ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "About you"; color: Colors.ink; font.pixelSize: 20; font.bold: true; font.family: Properties.fontFamily }
                            NetCard {
                                Layout.fillWidth: true
                                NetRow {
                                    first: true
                                    label: "Your name"
                                    desc: "the dashboard and lock screen greet you with it"
                                    TextControl {
                                        value: Settings.profile.name || Quickshell.env("USER") || ""
                                        onEdited: v => Settings.set("profile", "name", v.trim().slice(0, 40))
                                    }
                                }
                                NetRow {
                                    label: "Picture"
                                    desc: "shown next to the greeting"
                                    ActionButton { icon: "󰀄"; text: "Choose…"; onClicked: Panels.call("settings", "openPage", "profile") }
                                }
                                NetRow {
                                    label: "Compositor"
                                    desc: Compositor.isNiri ? "niri: keybinds, monitors and settings edit your niri config (validated before saving)"
                                        : Compositor.isHyprland ? "Hyprland: keybinds, monitors and settings edit your Hyprland config" : "not detected"
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // ── 2 bar ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "Your bar"; color: Colors.ink; font.pixelSize: 20; font.bold: true; font.family: Properties.fontFamily }
                            Text { text: "Pick a starting point; the bar at the top changes right away. Fine-tune it later in Settings → Bar layout."; color: Colors.fade(0.7); font.pixelSize: 13; font.family: Properties.fontFamily; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Repeater {
                                model: root.presets
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    // the preset from root.presets: modelData's nested lists aren't plain arrays
                                    readonly property var layout: root.presets[index].layout
                                    readonly property bool selected: JSON.stringify(BarLayout.globalLayout) === JSON.stringify(BarLayout.sanitize(layout))
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: 12
                                    color: selected ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16) : pm.containsMouse ? Colors.fade(0.07) : Colors.fade(0.03)
                                    border.width: 1
                                    border.color: selected ? Colors.color6 : Colors.fade(0.1)
                                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: BarLayout.save("", parent.layout) }
                                    ColumnLayout {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                                        spacing: 2
                                        Text { text: (parent.parent.selected ? "󰄬  " : "") + parent.parent.modelData.name; color: Colors.ink; font.pixelSize: 14; font.bold: true; font.family: Properties.fontFamily }
                                        Text { text: parent.parent.modelData.desc; color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // ── 3 notifications & updates ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "Notifications and updates"; color: Colors.ink; font.pixelSize: 20; font.bold: true; font.family: Properties.fontFamily }
                            NetCard {
                                Layout.fillWidth: true
                                NetRow {
                                    first: true
                                    label: "Quiet at night"
                                    desc: "do not disturb from 22:00 to 07:00 (critical ones still show)"
                                    ToggleSwitch {
                                        checked: Settings.notifications.scheduleOn ?? false
                                        onToggled: v => Settings.set("notifications", "scheduleOn", v)
                                    }
                                }
                                NetRow {
                                    label: "Popups appear"
                                    DropdownControl {
                                        options: [{ label: "Top right", value: "top-right" }, { label: "Top centre", value: "top-center" },
                                                  { label: "Top left", value: "top-left" }, { label: "Bottom right", value: "bottom-right" }, { label: "Bottom left", value: "bottom-left" }]
                                        value: Notifs.position
                                        onEdited: v => Settings.set("notifications", "position", v)
                                    }
                                }
                                NetRow {
                                    label: "Tell me about new updates"
                                    desc: "a notification when packages can be updated (checked every 30 min)"
                                    ToggleSwitch { checked: Settings.updates.notify ?? false; onToggled: v => Settings.set("updates", "notify", v) }
                                }
                                NetRow {
                                    label: "Include the AUR"
                                    ToggleSwitch { checked: Updates.withAur; onToggled: v => Settings.set("updates", "aur", v) }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // ── 4 look & keys ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "Look and keys"; color: Colors.ink; font.pixelSize: 20; font.bold: true; font.family: Properties.fontFamily }
                            NetCard {
                                Layout.fillWidth: true
                                NetRow {
                                    first: true
                                    label: "Wallpaper and colors"
                                    desc: "pick a wallpaper; the colors of the whole shell follow it (pywal)"
                                    ActionButton { icon: "󰸉"; text: "Pick a wallpaper"; onClicked: Panels.toggle("wallpapers") }
                                }
                                NetRow {
                                    label: "Light or dark, saved themes"
                                    desc: "Settings → Shell → Theme"
                                }
                                NetRow {
                                    label: "All keybinds"
                                    desc: "the launcher's keyboard tab lists them; record and change them in Settings → Keybinds"
                                    ActionButton { icon: "󰌌"; text: "Show keybinds"; onClicked: Panels.toggle("keybinds") }
                                }
                                NetRow {
                                    label: "Screenshots"
                                    desc: "Print: capture menu · Ctrl+Print: whole screen · Shift+Print: start / stop recording"
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // ── 5 done ──
                        ColumnLayout {
                            spacing: 14
                            Text { text: "All set"; color: Colors.ink; font.pixelSize: 24; font.bold: true; font.family: Properties.fontFamily }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                text: "Everything else lives in the settings app: network, audio, Bluetooth, default apps, connections, profiles and more. This setup can be run again from Settings → Maintenance → Health."
                                color: Colors.fade(0.7); font.pixelSize: 13; font.family: Properties.fontFamily
                            }
                            ActionButton { icon: "󰒓"; text: "Open the settings app"; onClicked: { root.finish(); Panels.open("settings") } }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton { text: "Skip setup"; visible: root.step < root.steps.length - 1; onClicked: root.finish() }
                        Item { Layout.fillWidth: true }
                        ActionButton { icon: "󰁍"; text: "Back"; visible: root.step > 0; onClicked: root.step-- }
                        ActionButton {
                            icon: root.step === root.steps.length - 1 ? "󰄬" : "󰁔"
                            text: root.step === root.steps.length - 1 ? "Finish" : "Next"
                            primary: true
                            onClicked: root.step === root.steps.length - 1 ? root.finish() : root.step++
                        }
                    }
                }
            }
        }
    }
}
