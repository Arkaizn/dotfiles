import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// The file manager's preferences (⋮ → Preferences, Ctrl+,): the same spec as
// Settings → Apps → Files (FmSettings.sections), written through Settings.set
// (this process hands them to the shell: Settings.remote).
//   FmPrefs { }   open()
Modal {
    id: root

    cardWidth: 620

    function value(sp) { return Settings.files[sp.key] ?? sp.def }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Files preferences"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
            IconButton { icon: "󰅖"; tooltip: "Close  (Esc)"; onClicked: root.close() }
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Also in the Settings app: Apps → Files"
                color: Colors.fade(0.45); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
            }
            // the shell's Settings app on the Files page (the shell runs it: IPC)
            ActionButton {
                text: "Open in Settings"
                variant: "ghost"
                onClicked: { Jobs.run(["qs", "ipc", "-p", Quickshell.shellDir, "call", "settings", "openPage", "files"], () => {}); root.close() }
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(col.implicitHeight, Tokens.size.row * 11)
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SlimScrollBar {}
            SmoothWheel { flick: flick; step: 100 }

            ColumnLayout {
                id: col
                width: flick.width - Tokens.space.s12
                spacing: Tokens.space.s14
                Repeater {
                    model: FmSettings.sections()
                    Section {
                        id: sec
                        required property var modelData
                        Layout.fillWidth: true
                        title: modelData.title
                        Repeater {
                            model: sec.modelData.items
                            SettingRow {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property var sp: modelData
                                first: index === 0
                                label: sp.label
                                desc: sp.desc ?? ""
                                changed: Settings.files[sp.key] !== undefined && Settings.files[sp.key] !== sp.def
                                ToggleSwitch {
                                    visible: row.sp.type === "bool"
                                    checked: row.sp.type === "bool" && root.value(row.sp) === true
                                    accessibleName: row.sp.label
                                    onToggled: v => Settings.set("files", row.sp.key, v)
                                }
                                // a few choices: buttons side by side, like the Settings app
                                Segmented {
                                    visible: row.sp.type === "choice"
                                    options: row.sp.options ?? []
                                    value: row.sp.type === "choice" ? root.value(row.sp) : ""
                                    onEdited: v => Settings.set("files", row.sp.key, v)
                                }
                                Stepper {
                                    visible: row.sp.type === "int"
                                    from: row.sp.min ?? 0
                                    to: row.sp.max ?? 9999
                                    value: row.sp.type === "int" ? root.value(row.sp) : 0
                                    onEdited: v => Settings.set("files", row.sp.key, v)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
