import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Theme page (services/Theme.qml): current pywal colors, a preview made from
// the wallpaper (dark / light, backend, saturation), saved themes and pywal's
// built-in ones. Nothing changes until Apply.
ColumnLayout {
    id: page
    spacing: 16

    property bool light: false
    property string backend: "wal"
    property real saturate: -1              // -1 = wal's default
    property string themeQuery: ""
    property string newName: ""
    property string saveMsg: ""

    Component.onCompleted: { Theme.refresh(); Theme.loadBuiltins() }

    readonly property var shownBuiltins: {
        const q = themeQuery.trim().toLowerCase()
        return Theme.builtins.filter(t => (q === "" || t.name.toLowerCase().includes(q)) && t.light === page.light)
    }

    // ── Current ─────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Current colors"
        header: ActionButton {
            icon: "󰕌"; text: "Undo last apply"
            interactive: Theme.hasUndo && !Theme.applying
            onClicked: Theme.undo()
        }
        NetRow {
            first: true
            wide: true
            label: Theme.current ? "From " + Theme.wallpaper.replace(Theme.home, "~") : "No pywal colors yet"
            desc: Theme.current ? "~/.cache/wal/colors.json" : "pick a wallpaper in the launcher, or apply a theme below"
            RowLayout {
                spacing: 14
                visible: Theme.current !== null
                ThemeSwatches { colors: Theme.current?.colors ?? ({}); size: 18 }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // ── Preview ─────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Make a scheme from the wallpaper"
        NetRow {
            first: true
            label: "Mode"
            Segmented {
                small: true
                options: [{ label: "Dark", value: false }, { label: "Light", value: true }]
                value: page.light
                onEdited: v => page.light = v
            }
        }
        NetRow {
            label: "Backend"
            desc: Theme.backends.length > 1 ? "how colors are picked from the image" : "only wal's own is installed (python-colorthief etc. add more)"
            DropdownControl {
                options: Theme.backends.map(b => ({ label: b, value: b }))
                value: page.backend
                onEdited: v => page.backend = v
            }
        }
        NetRow {
            label: "Saturation"
            desc: page.saturate < 0 ? "wal's default" : String(page.saturate)
            RowLayout {
                spacing: 8
                ToggleSwitch { checked: page.saturate >= 0; onToggled: v => page.saturate = v ? 0.5 : -1 }
                NumberControl {
                    visible: page.saturate >= 0
                    from: 0; to: 1; step: 0.1
                    value: Math.max(0, page.saturate)
                    onEdited: v => page.saturate = Math.round(v * 10) / 10
                }
            }
        }
        NetRow {
            label: "Preview"
            desc: Theme.previewing ? "running wal…" : "nothing changes until you apply"
            ActionButton {
                icon: Theme.previewing ? "󰜺" : "󰈈"
                text: Theme.previewing ? "Cancel" : "Preview"
                primary: !Theme.previewing
                onClicked: Theme.previewing ? Theme.cancelPreview()
                                            : Theme.previewWallpaper({ light: page.light, backend: page.backend, saturate: page.saturate })
            }
        }
    }

    // the preview (from the wallpaper, a saved theme or a built-in one)
    NetCard {
        Layout.fillWidth: true
        visible: Theme.preview !== null || Theme.error !== ""
        title: "Preview"
        tint: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.06)
        NetRow {
            first: true
            visible: Theme.error !== ""
            label: "Problem"
            desc: Theme.error
        }
        NetRow {
            first: Theme.error === ""
            visible: Theme.preview !== null
            wide: true
            label: Theme.preview?.name ?? ""
            desc: "background " + (Theme.preview?.special?.background ?? "") + "  ·  foreground " + (Theme.preview?.special?.foreground ?? "")
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                ThemeSample { scheme: Theme.preview }
                ThemeSwatches { colors: Theme.preview?.colors ?? ({}); rows: 2; size: 20 }
                Item { Layout.fillWidth: true }
                ActionButton {
                    icon: "󰄬"
                    text: Theme.applying ? "Applying…" : "Apply"
                    primary: true
                    interactive: !Theme.applying
                    onClicked: Theme.apply(Theme.preview.file)
                }
            }
        }
    }

    // ── Saved ───────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Saved themes"
        NetRow {
            first: true
            label: "Save the current colors"
            desc: page.saveMsg !== "" ? page.saveMsg : Theme.savedDir.replace(Theme.home, "~")
            RowLayout {
                spacing: 8
                SearchField {
                    Layout.preferredWidth: 200
                    icon: ""; clearable: false
                    placeholderText: "name"
                    text: page.newName
                    onTextEdited: page.newName = text
                    onAccepted: saveBtn.clicked()
                }
                ActionButton {
                    id: saveBtn
                    icon: "󰆓"; text: "Save"
                    interactive: Theme.current !== null
                    onClicked: {
                        const exists = Theme.saved.some(t => t.name === page.newName.trim())
                        if (exists && page.saveMsg !== "overwrite? press Save again") { page.saveMsg = "overwrite? press Save again"; return }
                        Theme.save(page.newName, (ok, msg) => { page.saveMsg = ok ? "saved" : msg; if (ok) page.newName = "" })
                    }
                }
            }
        }
        Repeater {
            model: Theme.saved
            NetRow {
                required property var modelData
                label: modelData.name
                RowLayout {
                    spacing: 8
                    ThemeSwatches { colors: modelData.data.colors; size: 12 }
                    IconButton { icon: "󰈈"; tooltip: "Preview"; onClicked: Theme.previewFile(modelData.name, modelData.file, modelData.data) }
                    IconButton { icon: "󰄬"; tooltip: "Apply"; interactive: !Theme.applying; onClicked: Theme.apply(modelData.file) }
                    IconButton {
                        id: del
                        property bool armed: false
                        icon: armed ? "󰄬" : "󰆴"
                        tooltip: armed ? "Click again to delete" : "Delete"
                        textColor: armed ? "#f38ba8" : Properties.color
                        onClicked: { if (armed) Theme.remove(modelData.name); else { armed = true; disarm.restart() } }
                        Timer { id: disarm; interval: 3000; onTriggered: del.armed = false }
                    }
                }
            }
        }
    }

    // ── Built-in ────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "pywal themes (" + (page.light ? "light" : "dark") + ")"
        header: SearchField {
            Layout.preferredWidth: 220
            placeholderText: "Search themes"
            text: page.themeQuery
            onTextEdited: page.themeQuery = text
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.min(320, list.contentHeight + 12)
            ListView {
                id: list
                anchors { fill: parent; margins: 6 }
                clip: true
                model: page.shownBuiltins
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 34
                    radius: 8
                    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Theme.previewFile(row.modelData.name, row.modelData.file, row.modelData.data) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        Text { Layout.fillWidth: true; text: row.modelData.name; color: "white"; font.pixelSize: 12; font.family: Properties.fontFamily; elide: Text.ElideRight }
                        ThemeSwatches { colors: row.modelData.data.colors; size: 12 }
                    }
                }
            }
        }
    }
}
