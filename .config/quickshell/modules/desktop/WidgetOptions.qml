import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../settings/network"

// The options of one desktop widget (DesktopWidgets.specs), as rows: used by
// the live editor and Settings → Desktop widgets. Changes save right away.
ColumnLayout {
    id: root
    property string instId: ""
    readonly property var inst: DesktopWidgets.byId[instId] ?? null
    readonly property var opts: DesktopWidgets.optsOf(inst)
    readonly property var specs: inst ? DesktopWidgets.specs(inst.type) : []
    property bool firstRow: true            // the first row draws no divider
    signal choosingFile(bool on)            // a file dialog is open (the editor steps aside)

    spacing: 0
    function set(k, v) { DesktopWidgets.setOpt(instId, k, v) }

    Repeater {
        model: root.specs
        NetRow {
            id: row
            required property var modelData
            required property int index
            readonly property var spec: modelData
            readonly property var val: root.opts[spec.key]
            first: index === 0 && root.firstRow
            label: spec.label
            wide: spec.kind === "list" || (spec.kind === "text" && spec.multiline === true)
            changed: root.inst?.opts?.[spec.key] !== undefined && JSON.stringify(root.inst.opts[spec.key]) !== JSON.stringify(spec.def)

            ToggleSwitch {
                visible: row.spec.kind === "bool"
                checked: row.val === true
                onToggled: v => root.set(row.spec.key, v)
            }
            NumberControl {
                visible: row.spec.kind === "number"
                from: row.spec.min ?? 0
                to: row.spec.max ?? 100
                step: row.spec.step ?? 1
                value: typeof row.val === "number" ? row.val : 0
                onEdited: v => root.set(row.spec.key, v)
            }
            DropdownControl {
                visible: row.spec.kind === "choice"
                implicitWidth: 180
                options: row.spec.choices ?? []
                value: row.val
                onEdited: v => root.set(row.spec.key, v)
            }
            TextControl {
                visible: row.spec.kind === "text" && row.spec.multiline !== true
                implicitWidth: 220
                value: typeof row.val === "string" ? row.val : ""
                onEdited: v => root.set(row.spec.key, v)
            }
            ActionButton {
                visible: row.spec.file === true
                icon: "󰉋"
                text: "Choose…"
                onClicked: {
                    root.choosingFile(true)
                    Jobs.run(["zenity", "--file-selection", "--title=Choose a picture",
                              "--file-filter=Pictures | *.png *.jpg *.jpeg *.webp *.gif *.svg *.bmp"], (code, out) => {
                        root.choosingFile(false)
                        if (code === 0 && out.trim() !== "") root.set(row.spec.key, out.trim())
                    })
                }
            }
            // multi-line text (note): saved half a second after typing stops
            TextArea {
                id: area
                visible: row.spec.kind === "text" && row.spec.multiline === true
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(220, Math.max(70, contentHeight + 20))
                text: typeof row.val === "string" ? row.val : ""
                onTextChanged: if (activeFocus) saveText.restart()
                wrapMode: TextEdit.Wrap
                color: Colors.ink
                selectionColor: Colors.fade(0.28)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle {
                    radius: 10
                    color: Colors.fade(0.05)
                    border.width: 1
                    border.color: area.activeFocus ? Colors.color6 : Colors.fade(0.12)
                }
                Timer { id: saveText; interval: 500; onTriggered: root.set(row.spec.key, area.text) }
            }
            // list of apps / folders
            ColumnLayout {
                visible: row.spec.kind === "list"
                Layout.fillWidth: true
                spacing: 6
                readonly property var items: Array.isArray(row.val) ? row.val : []
                Repeater {
                    model: parent.items
                    RowLayout {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        Text {
                            visible: row.spec.item === "app"
                            Layout.fillWidth: true
                            text: modelData
                            elide: Text.ElideRight
                            color: Colors.ink
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                        TextControl {
                            visible: row.spec.item !== "app"
                            Layout.fillWidth: true
                            value: modelData
                            onEdited: v => { const l = row.val.slice(); l[index] = v; root.set(row.spec.key, l) }
                        }
                        IconButton {
                            icon: "󰁝"; tooltip: "Earlier"
                            interactive: index > 0
                            onClicked: { const l = row.val.slice(); l.splice(index - 1, 0, l.splice(index, 1)[0]); root.set(row.spec.key, l) }
                        }
                        IconButton {
                            icon: "󰅖"; tooltip: "Remove"
                            onClicked: root.set(row.spec.key, row.val.filter((_, i) => i !== index))
                        }
                    }
                }
                AppPicker {
                    visible: row.spec.item === "app"
                    implicitWidth: 280
                    value: ""
                    onPicked: (v, name) => root.set(row.spec.key, (Array.isArray(row.val) ? row.val : []).concat([v]))
                }
                ActionButton {
                    visible: row.spec.item === "path"
                    icon: "󰐕"
                    text: "Add folder"
                    onClicked: root.set(row.spec.key, (Array.isArray(row.val) ? row.val : []).concat([Quickshell.env("HOME")]))
                }
            }
        }
    }
}
