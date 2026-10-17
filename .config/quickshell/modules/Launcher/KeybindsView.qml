import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../keybinds"

// Keybinds tab of the launcher: a "Most important" card on top, then every
// keybind (services/Keybinds.qml) grouped in category cards, 4 columns.
// The launcher's search field filters (description, keys or category).
// Same interface as the other launcher views (query, active, moveUp/Down…).
Item {
    id: root

    property int maxHeight: 520
    property string query: ""
    property bool active: false
    signal closeRequested()

    readonly property int columns: 4
    implicitHeight: maxHeight

    // re-read the compositor config each time the tab opens
    onActiveChanged: if (active) { Keybinds.refresh(); flick.contentY = 0 }

    function moveDown() { wheel.scrollBy(90) }
    function moveUp() { wheel.scrollBy(-90) }
    function activateCurrent() {}

    function matches(b, catName) {
        const q = query.trim().toLowerCase()
        return q === "" || (b.desc + " " + catName + " " + b.combos.map(k => k.map(x => Keybinds.keyLabel(x)).join(" ")).join(" "))
            .toLowerCase().includes(q)
    }

    readonly property var cards: {
        const out = []
        for (const c of Keybinds.categories) {
            const rows = Keybinds.binds.filter(b => b.category === c.name && root.matches(b, c.name))
            if (rows.length > 0) out.push({ name: c.name, icon: c.icon, rows: rows })
        }
        return out
    }

    // each card goes into the column that's shortest so far (by row count)
    readonly property var layout: {
        const cols = [], heights = []
        for (let i = 0; i < columns; i++) { cols.push([]); heights.push(0) }
        for (const c of cards) {
            let min = 0
            for (let i = 1; i < columns; i++) if (heights[i] < heights[min]) min = i
            cols[min].push(c)
            heights[min] += 2.2 + c.rows.reduce((n, r) => n + r.combos.length, 0)
        }
        return cols
    }

    readonly property bool showImportant: query.trim() === "" && Keybinds.important.length > 0

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        SmoothWheel { id: wheel; flick: flick; step: 110 }

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 10

            // where the binds come from / errors
            Text {
                Layout.leftMargin: 4
                text: Keybinds.error !== "" ? "󰀦  " + Keybinds.error
                    : Keybinds.binds.length + " shortcuts from your " + (Compositor.name || "niri") + " config"
                color: Keybinds.error !== "" ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }

            // ── Most important ──
            Rectangle {
                Layout.fillWidth: true
                visible: root.showImportant
                implicitHeight: impCol.implicitHeight + 22
                radius: 14
                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08)
                border.width: Properties.panelBorderWidth
                border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.35)

                ColumnLayout {
                    id: impCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11; leftMargin: 14; rightMargin: 14 }
                    spacing: 6

                    RowLayout {
                        spacing: 8
                        Text {
                            text: "󰓎"
                            color: Colors.color6
                            font.pixelSize: 15
                            font.family: Properties.fontFamily
                        }
                        Text {
                            text: "Most important"
                            color: "white"
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 24
                        rowSpacing: 0
                        Repeater {
                            model: root.showImportant ? Keybinds.important : []
                            BindRow {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1      // equal columns
                                bind: modelData
                            }
                        }
                    }
                }
            }

            // ── All, 4 columns ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: root.columns
                    ColumnLayout {
                        id: column
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1              // equal widths
                        Layout.alignment: Qt.AlignTop
                        spacing: 8
                        Repeater {
                            model: root.layout[column.index]
                            KeyCategoryCard {
                                required property var modelData
                                Layout.fillWidth: true
                                category: modelData
                                compact: true
                            }
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 30
                visible: root.cards.length === 0 && Keybinds.error === ""
                text: root.query !== "" ? "No keybind matches \"" + root.query + "\"" : "No keybinds"
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 13
                font.family: Properties.fontFamily
            }

            Item { implicitHeight: 4 }
        }
    }
}
