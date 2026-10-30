import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"
import "../../calendar"

// Icons page: the shell's font (a Nerd Font, from the installed ones) and every
// named icon (services/Icons.qml). Click an icon to change it: search the
// font's icons by name (names come from the font: scripts/nerd-glyphs.py),
// or paste a glyph / type its code (e.g. f08c7). Above them: the colored icons
// (trash red, archive blue, …), each on / off.
ColumnLayout {
    id: page
    spacing: 16

    property var glyphs: []                 // [{ g: glyph, name }]
    property string glyphError: ""
    property string editing: ""             // icon id whose picker is open
    property string query: ""

    // Nerd Fonts installed (by family), plus the current one
    readonly property var nerdFonts: {
        const fams = Qt.fontFamilies().filter(f => /Nerd Font|\bNF[MP]?\b/.test(f))
        if (!fams.includes(Properties.fontFamily)) fams.push(Properties.fontFamily)
        return [...new Set(fams)].sort()
    }

    Component.onCompleted: loadGlyphs()
    Connections { target: Properties; function onFontFamilyChanged() { page.loadGlyphs() } }

    function loadGlyphs() {
        Jobs.run(["python3", "-I", Quickshell.shellDir + "/scripts/nerd-glyphs.py", Properties.fontFamily], (code, out, err) => {
            if (code !== 0) { glyphError = /fontTools/.test(err) ? "python-fonttools isn't installed (for the icon search)" : err.trim().split("\n").pop(); glyphs = []; return }
            glyphError = ""
            glyphs = out.split("\n").map(l => l.split("\t")).filter(p => p.length === 2)
                        .map(p => ({ g: String.fromCodePoint(parseInt(p[0], 16)), name: p[1] }))
        })
    }

    // what the picker shows: matches of the search, else the neighbours of the
    // current icon (similar icons sit next to each other in the font)
    readonly property var results: {
        const q = query.trim().toLowerCase()
        if (q !== "") {
            const words = q.split(/\s+/)
            return glyphs.filter(x => words.every(w => x.name.includes(w))).slice(0, 240)
        }
        if (editing === "") return []
        const i = glyphs.findIndex(x => x.g === Icons.get(editing))
        return i < 0 ? glyphs.slice(0, 120) : glyphs.slice(Math.max(0, i - 60), i + 60)
    }
    function nameOf(g) { return glyphs.find(x => x.g === g)?.name ?? "" }

    // pasted glyph, or a hex code (f08c7 / U+F08C7 / 0xf08c7)
    function parseInput(t) {
        t = t.trim()
        const m = /^(?:u\+|0x)?([0-9a-f]{4,6})$/i.exec(t)
        if (m) return String.fromCodePoint(parseInt(m[1], 16))
        return t.length > 0 && t.length <= 4 ? t : ""
    }

    NetCard {
        Layout.fillWidth: true
        title: "Font"
        icon: "󰛖"
        NetRow {
            first: true
            label: "Shell font"
            desc: page.nerdFonts.length + " Nerd Fonts installed · the icons come from it, so it has to be a Nerd Font"
            DropdownControl {
                implicitWidth: 260
                options: page.nerdFonts.map(f => ({ label: f, value: f }))
                value: Properties.fontFamily
                onEdited: v => Settings.set("properties", "fontFamily", v)
            }
        }
    }

    // icons colored by what they do (Icons.colorList), each one on / off
    NetCard {
        Layout.fillWidth: true
        title: "Colors"
        icon: "󰏘"
        Repeater {
            model: Icons.colorList
            NetRow {
                id: colorRow
                required property var modelData
                required property int index
                readonly property bool on: Icons.colorOn(modelData.id)
                first: index === 0
                changed: !on
                label: modelData.label + " in color"
                desc: modelData.desc
                RowLayout {
                    spacing: 12
                    Text {
                        text: colorRow.modelData.glyph
                        color: colorRow.on ? Icons.colorOf(colorRow.modelData.id) : Properties.color
                        Behavior on color { ColorAnimation { duration: 200 } }
                        font.pixelSize: 18
                        font.family: Properties.fontFamily
                    }
                    ToggleSwitch { checked: colorRow.on; onToggled: v => Icons.setColorOn(colorRow.modelData.id, v) }
                }
            }
        }
    }

    Repeater {
        model: Icons.groups
        NetCard {
            id: groupCard
            required property string modelData
            Layout.fillWidth: true
            title: modelData
            Repeater {
                model: Icons.list.filter(i => i.group === groupCard.modelData)
                NetRow {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string glyph: Icons.get(modelData.id)
                    readonly property bool isChanged: glyph !== modelData.glyph
                    readonly property bool open: page.editing === modelData.id
                    first: index === 0
                    wide: open
                    changed: isChanged
                    label: modelData.label
                    desc: isChanged ? "default " + modelData.glyph + "  ·  " + (page.nameOf(glyph) || "custom")
                                    : page.nameOf(glyph)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 6
                            IconButton {
                                visible: row.isChanged
                                icon: "󰑓"
                                iconSize: 13
                                tooltip: "Back to " + row.modelData.glyph
                                onClicked: Icons.set(row.modelData.id, "")
                            }
                            // the icon itself: click to change
                            Rectangle {
                                implicitWidth: 44; implicitHeight: 36
                                radius: Properties.radius
                                color: row.open ? Colors.fade(0.14) : glyphHover.hovered ? Colors.fade(0.1) : Colors.fade(0.05)
                                border.width: 1
                                border.color: row.open ? Colors.color6 : Colors.fade(0.12)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: row.glyph
                                    color: Colors.ink
                                    font.pixelSize: 20
                                    font.family: Properties.fontFamily
                                }
                                HoverHandler { id: glyphHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        page.query = ""
                                        page.editing = row.open ? "" : row.modelData.id
                                    }
                                }
                            }
                        }

                        // ── picker ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: row.open
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                SearchField {
                                    id: search
                                    Layout.fillWidth: true
                                    placeholderText: "Search icons by name (e.g. arch, wifi, music)"
                                    text: page.query
                                    onTextEdited: page.query = text
                                    Component.onCompleted: if (row.open) forceActiveFocus()
                                }
                                SearchField {
                                    Layout.preferredWidth: 170
                                    icon: "󰆒"
                                    placeholderText: "paste / code (f08c7)"
                                    onAccepted: { const g = page.parseInput(text); if (g) { Icons.set(row.modelData.id, g); text = "" } }
                                }
                                ActionButton {
                                    icon: "󰖟"
                                    text: "Cheat sheet"
                                    onClicked: Qt.openUrlExternally("https://www.nerdfonts.com/cheat-sheet")
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: page.glyphError !== "" ? "󰀦 " + page.glyphError
                                    : page.query.trim() !== "" ? page.results.length + (page.results.length === 240 ? "+" : "") + " found"
                                    : "Icons next to the current one (similar ones are grouped in the font) · search to find others"
                                color: page.glyphError !== "" ? Colors.red : Colors.fade(0.45)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }

                            GridView {
                                id: grid
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(4, Math.ceil(count / Math.max(1, Math.floor(width / cellWidth)))) * cellHeight
                                cellWidth: 46
                                cellHeight: 46
                                clip: true
                                model: row.open ? page.results : []
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: CalScrollBar {}
                                SmoothWheel { flick: grid; step: 92 }

                                delegate: Item {
                                    id: cell
                                    required property var modelData
                                    readonly property bool current: modelData.g === row.glyph
                                    width: grid.cellWidth
                                    height: grid.cellHeight
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        radius: Properties.radius
                                        color: cell.current ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.22)
                                             : cellHover.hovered ? Colors.fade(0.1) : "transparent"
                                        border.width: cell.current ? 1 : 0
                                        border.color: Colors.color6
                                        scale: cellHover.hovered ? 1.12 : 1
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: cell.modelData.g
                                            color: Colors.ink
                                            font.pixelSize: 20
                                            font.family: Properties.fontFamily
                                        }
                                    }
                                    HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Icons.set(row.modelData.id, cell.modelData.g) }
                                    ToolTip.visible: cellHover.hovered
                                    ToolTip.delay: 300
                                    ToolTip.text: cell.modelData.name
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
