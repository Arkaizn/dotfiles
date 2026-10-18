import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../calendar"

// "All apps" page of the app launcher (AppSearch.qml, button next to
// "Recommended"): every app A–Z with a letter header per group, and a letter
// strip on the right that scrolls (animated) to that letter's apps. Letters
// with no apps are dimmed; clicking one jumps to the next letter that has some.
Item {
    id: root

    property var apps: []                 // already sorted by name
    signal launched(var entry)

    // # first (digits / symbols), then A–Z; accents count as their base letter
    function letterOf(e) {
        const c = (e.name || "").normalize("NFD").charAt(0).toUpperCase()
        return c >= "A" && c <= "Z" ? c : "#"
    }
    readonly property var letters: ["#"].concat("ABCDEFGHIJKLMNOPQRSTUVWXYZ".split(""))
    readonly property var items: {
        const all = apps.map(e => ({ entry: e, letter: letterOf(e) }))
        return all.filter(it => it.letter === "#").concat(all.filter(it => it.letter !== "#"))
    }
    // letter -> index of its first app
    readonly property var firstIndex: {
        const m = {}
        items.forEach((it, i) => { if (m[it.letter] === undefined) m[it.letter] = i })
        return m
    }
    // the letter of the group at the top of the list (highlighted in the strip)
    property string topLetter: "#"
    function updateTopLetter() {
        const i = list.indexAt(10, list.contentY + 2)
        if (i >= 0 && i < items.length) topLetter = items[i].letter
    }

    // smooth scroll to the first app of `l` (or the next letter that has apps)
    function jumpTo(l) {
        let i = letters.indexOf(l)
        while (i < letters.length && firstIndex[letters[i]] === undefined) i++
        if (i >= letters.length) return
        const idx = firstIndex[letters[i]]
        // where positionViewAtIndex would land, then animate there instead
        const from = list.contentY
        list.positionViewAtIndex(idx, ListView.Beginning)
        const to = Math.min(list.contentY, Math.max(list.originY, list.contentHeight + list.originY - list.height))
        list.contentY = from
        scrollAnim.stop()
        wheel.anim.stop()
        scrollAnim.to = to
        scrollAnim.start()
        list.currentIndex = idx
    }
    NumberAnimation { id: scrollAnim; target: list; property: "contentY"; duration: 320; easing.type: Easing.OutCubic }

    // keyboard nav (from AppSearch)
    function moveDown() { list.incrementCurrentIndex() }
    function moveUp() { list.decrementCurrentIndex() }
    function activateCurrent() { if (list.currentIndex >= 0) root.launched(items[list.currentIndex].entry) }
    function reset() { scrollAnim.stop(); list.currentIndex = -1; list.positionViewAtBeginning(); updateTopLetter() }

    RowLayout {
        anchors.fill: parent
        spacing: 6

        ListView {
            id: list
            // same wheel feel as the settings sidebar
            SmoothWheel { id: wheel; flick: list; step: 100 }
            // a wheel notch cancels a running letter jump
            Connections { target: wheel; function onWheel() { scrollAnim.stop() } }
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.items
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 80
            ScrollBar.vertical: CalScrollBar {}
            onContentYChanged: root.updateTopLetter()
            onMovementStarted: scrollAnim.stop()
            onCountChanged: root.updateTopLetter()

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool groupStart: index === 0 || root.items[index - 1].letter !== modelData.letter
                readonly property bool isCurrent: list.currentIndex === index
                width: list.width - 10
                height: (groupStart ? 26 : 0) + 40

                // letter header of the group
                Text {
                    visible: row.groupStart
                    x: 10
                    height: 26
                    verticalAlignment: Text.AlignBottom
                    bottomPadding: 3
                    text: row.modelData.letter
                    color: Colors.color6
                    font.pixelSize: 12
                    font.bold: true
                }

                Item {
                    id: appRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 40

                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: rowTap; onTapped: root.launched(row.modelData.entry) }

                    scale: rowTap.pressed ? Properties.onPressedButtonScale : 1
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 12
                        color: row.isCurrent ? Colors.fade(0.13) : rowHover.hovered ? Colors.fade(0.08) : "transparent"
                        border.color: row.isCurrent ? Colors.fade(0.22) : "transparent"
                        border.width: 0.5
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        IconImage {
                            implicitWidth: 22
                            implicitHeight: 22
                            source: Quickshell.iconPath(row.modelData.entry.icon, "AppImage")
                            // hovered icon nudges right a bit
                            transform: Translate {
                                x: rowHover.hovered ? 3 : 0
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.entry.name
                            color: row.isCurrent || rowHover.hovered ? Colors.ink : Colors.fade(0.75)
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        Text {
                            Layout.maximumWidth: 220
                            text: row.modelData.entry.comment || ""
                            color: Colors.fade(0.38)
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            opacity: rowHover.hovered || row.isCurrent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                    }
                }
            }
        }

        // ── A–Z strip ──
        // Spread over the full height. Hovering magnifies the letter under
        // the pointer and, less and less, its neighbours (dock-style), and
        // pulls them out to the left, towards you.
        Item {
            id: strip
            Layout.fillHeight: true
            Layout.preferredWidth: 30
            readonly property real cell: height / root.letters.length
            readonly property real reach: 3.2          // neighbours affected, in cells
            property real pointerY: -1000               // -1000 = not hovered

            HoverHandler {
                id: stripHover
                cursorShape: Qt.PointingHandCursor
                onPointChanged: strip.pointerY = point.position.y
                onHoveredChanged: if (!hovered) strip.pointerY = -1000
            }

            Repeater {
                model: root.letters
                Item {
                    id: cell
                    required property string modelData
                    required property int index
                    readonly property bool has: root.firstIndex[modelData] !== undefined
                    readonly property bool current: root.topLetter === modelData
                    // 1 under the pointer, fading to 0 `reach` cells away (smooth cosine falloff)
                    readonly property real near: {
                        const d = Math.abs(strip.pointerY - (y + height / 2)) / strip.cell
                        return d >= strip.reach ? 0 : (Math.cos(Math.PI * d / strip.reach) + 1) / 2
                    }
                    readonly property bool hovered: stripHover.hovered && Math.abs(strip.pointerY - (y + height / 2)) <= height / 2
                    x: 0
                    y: index * strip.cell
                    width: strip.width
                    height: strip.cell
                    z: near

                    TapHandler { onTapped: root.jumpTo(cell.modelData) }

                    Item {
                        anchors.fill: parent
                        // pulled out to the left and grown, by how near the pointer is
                        transform: Translate {
                            x: -10 * cell.near
                            Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        }

                        // pill behind the letter whose apps are at the top
                        Rectangle {
                            anchors.centerIn: parent
                            width: 20
                            height: Math.min(parent.height - 2, 18)
                            radius: 5
                            color: Colors.color6
                            opacity: cell.current ? 0.22 : 0
                            scale: cell.current ? 1 : 0.5
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.modelData
                            color: cell.current ? Colors.color6 : cell.hovered ? Colors.ink : Colors.fade(cell.has ? 0.6 : 0.2)
                            font.pixelSize: 11
                            font.bold: cell.current || cell.hovered
                            scale: 1 + (cell.has ? 0.9 : 0.4) * cell.near
                            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }
        }
    }
}
