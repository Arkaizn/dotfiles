import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

// Keybind cheatsheet: every niri bind (services/Keybinds.qml), grouped in
// dashboard-style cards. Hangs under the bar like the dashboard.
//
//   qs ipc call keybinds toggle      (also: the keyboard button in the control center)
//
// Re-reads the niri config each time it opens, so new binds show up right away.
BarPopup {
    id: root
    side: "center"
    ipcName: "keybinds"
    panelWidth: 1180
    // grows with the content up to the screen height, then scrolls
    maxHeight: (screen?.height ?? 1440) - 90
    panelHeight: Math.min(main.implicitHeight + padding * 2, maxHeight)
    Behavior on panelHeight {
        enabled: root.reveal === 1
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    // stays open while reading / typing with the pointer elsewhere
    autoClose: false

    // for the search field
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // inner cards: panel radius minus the padding, so the corners nest concentrically
    readonly property int radius: Properties.panelRadius - padding
    readonly property int columns: 3

    property string query: ""

    onOpening: {
        Keybinds.refresh()
        search.text = ""
        flick.contentY = 0
        search.forceActiveFocus()
    }

    // categories with their (filtered) rows, spread over the columns: each
    // card goes into the column that's shortest so far (by row count)
    readonly property var cards: {
        const q = query.trim().toLowerCase()
        const out = []
        for (const c of Keybinds.categories) {
            const rows = Keybinds.binds.filter(b => b.category === c.name && (q === ""
                || (b.desc + " " + c.name + " " + b.combos.map(k => k.map(x => Keybinds.keyLabel(x)).join(" ")).join(" "))
                       .toLowerCase().includes(q)))
            if (rows.length > 0) out.push({ name: c.name, icon: c.icon, rows: rows })
        }
        return out
    }
    readonly property var layout: {
        const cols = []
        const heights = []
        for (let i = 0; i < columns; i++) { cols.push([]); heights.push(0) }
        for (const c of cards) {
            let min = 0
            for (let i = 1; i < columns; i++) if (heights[i] < heights[min]) min = i
            cols[min].push(c)
            heights[min] += 2.2 + c.rows.reduce((n, r) => n + r.combos.length, 0)
        }
        return cols
    }

    ColumnLayout {
        id: main
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.panelHeight - root.padding * 2
        spacing: 10

        // ── Header ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 20
            radius: root.radius
            color: '#45000000'
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder

            RowLayout {
                id: headerRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 10 }
                spacing: 12

                Text {
                    text: "󰌌"
                    color: Colors.color6
                    font.pixelSize: 26
                    font.family: Properties.fontFamily
                }
                ColumnLayout {
                    spacing: -2
                    Text {
                        text: "Keybinds"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    Text {
                        text: Keybinds.error !== "" ? Keybinds.error
                            : Keybinds.binds.length + " shortcuts from your niri config"
                        color: Keybinds.error !== "" ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                    }
                }

                Item { Layout.fillWidth: true }

                SearchField {
                    id: search
                    Layout.preferredWidth: 300
                    placeholderText: "Search keybinds"
                    onTextChanged: { root.query = text; flick.contentY = 0 }
                    Keys.onEscapePressed: text !== "" ? text = "" : root.close()
                }
                IconButton {
                    icon: "󰑓"
                    tooltip: "Reload from niri config"
                    onClicked: Keybinds.refresh()
                }
                IconButton {
                    icon: "󰅖"
                    tooltip: "Close"
                    onClicked: root.close()
                }
            }
        }

        // ── Cards ──
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            implicitHeight: Math.max(80, cols.implicitHeight)
            contentHeight: cols.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Text {
                x: (flick.width - width) / 2
                y: 30
                visible: root.cards.length === 0
                text: root.query !== "" ? "Nothing matches \"" + root.query + "\"" : "No keybinds"
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 13
                font.family: Properties.fontFamily
            }

            RowLayout {
                id: cols
                width: flick.width
                spacing: 10

                Repeater {
                    model: root.columns
                    ColumnLayout {
                        id: column
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1          // equal widths
                        Layout.alignment: Qt.AlignTop
                        spacing: 10

                        Repeater {
                            model: root.layout[column.index]
                            CategoryCard {
                                required property var modelData
                                Layout.fillWidth: true
                                category: modelData
                                radius: root.radius / 4 * 3
                            }
                        }
                    }
                }
            }
        }
    }

    // ── One category ──
    component CategoryCard: Rectangle {
        id: card
        property var category
        implicitHeight: cardCol.implicitHeight + 20
        color: '#45000000'
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 2

            RowLayout {
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                spacing: 8
                Text {
                    text: card.category.icon
                    color: Colors.color6
                    font.pixelSize: 15
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: card.category.name
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    text: card.category.rows.length
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }

            Repeater {
                model: card.category.rows
                BindRow {
                    required property var modelData
                    Layout.fillWidth: true
                    bind: modelData
                }
            }
        }
    }

    // ── One shortcut: what it does on the left, its key combo(s) on the right ──
    component BindRow: Rectangle {
        id: row
        property var bind
        implicitHeight: Math.max(30, rowLayout.implicitHeight + 8)
        radius: 8
        color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        HoverHandler { id: rowHover }

        RowLayout {
            id: rowLayout
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 4 }
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: row.bind.desc
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }

            // alternatives stacked, right-aligned
            ColumnLayout {
                spacing: 4
                Repeater {
                    model: row.bind.combos
                    RowLayout {
                        required property var modelData
                        Layout.alignment: Qt.AlignRight
                        spacing: 4
                        Repeater {
                            model: modelData
                            Keycap {
                                required property string modelData
                                key: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // ── A key: little raised cap, modifiers tinted ──
    component Keycap: Item {
        id: cap
        property string key
        readonly property bool modifier: Keybinds.isModifier(key)
        implicitWidth: Math.max(24, label.implicitWidth + 14)
        implicitHeight: 24

        // the "side" of the key, peeking out below the top
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 2
            radius: 6
            color: cap.modifier ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: cap.modifier ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45) : Qt.rgba(1, 1, 1, 0.16)

            Text {
                id: label
                anchors.centerIn: parent
                text: Keybinds.keyLabel(cap.key)
                color: cap.modifier ? Colors.color6 : "white"
                font.pixelSize: 11
                font.bold: true
                font.family: Properties.fontFamily
            }
        }
    }
}
