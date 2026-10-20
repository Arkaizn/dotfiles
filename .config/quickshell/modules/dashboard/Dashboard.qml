import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import "."

// Dashboard: profile, music, calendar, system stats — as cards in three
// columns (which card sits where: PanelLayout). Long-press an empty spot to
// edit live: cards wiggle, drag one to another column / position, − hides it,
// the bar on top puts hidden ones back.
// Window/shape/animation all come from BarPopup.
BarPopup {
    id: root
    side: "center"
    ipcName: "dashboard"
    panelWidth: 1070
    // taller when a column holds more than fits (PanelLayout.dashHeight)
    panelHeight: PanelLayout.dashHeight + padding * 2 + (editing ? editBar.height + 10 : 0)
    // room for the edit bar, so the surface doesn't resize while it slides in
    maxHeight: Math.min(PanelLayout.dashHeight + padding * 2 + 50, (screen?.height ?? 1440) - 70)
    // inner cards: panel radius minus the padding, so the corners nest concentrically
    property int radius: Properties.panelRadius - padding

    readonly property bool editing: EditMode.target === "dashboard"
    autoClose: !editing
    Behavior on panelHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    onPopupClosed: if (editing) EditMode.stop()
    Connections {
        target: EditMode
        function onTargetChanged() {
            if (EditMode.target === "dashboard" && !root.shown) root.open()
            if (EditMode.target !== "dashboard") root.cancelDrag()
        }
    }

    // ── drag state ──────────────────────────────────────────────────────────
    // (the surface covers the screen while editing: the card follows the
    // pointer anywhere and snaps to the nearest column / spot when let go)
    fullscreen: editing
    property string dragId: ""
    property Item dragItem: null
    property point grab: Qt.point(0, 0)      // pointer offset inside the dragged card
    property point pointer: Qt.point(0, 0)   // overlay coordinates
    property real dragY: 0                   // pointer y, in `content` coordinates
    property int dropCol: -1                 // -2 = hide (the edit bar)
    property int dropIndex: 0

    function beginDrag(id, item, gx, gy) {
        dragId = id
        dragItem = item
        grab = Qt.point(gx, gy)
        dropCol = -1
        EditMode.dragging = true
    }
    function cancelDrag() {
        dragId = ""
        dragItem = null
        dropCol = -1
        EditMode.dragging = false
    }
    function endDrag() {
        if (dragId !== "" && dropCol === -2) PanelLayout.dashRemove(dragId)
        else if (dragId !== "" && dropCol >= 0) PanelLayout.dashMove(dragId, dropCol, dropIndex)
        cancelDrag()
    }
    function track(op) {
        pointer = op
        const b = editBar.mapFromItem(overlay, op.x, op.y)
        if (b.x >= 0 && b.y >= 0 && b.x <= editBar.width && b.y <= editBar.height) { dropCol = -2; return }
        const p = content.mapFromItem(overlay, op.x, op.y)
        dragY = p.y
        let col = -1, best = 1e9
        for (let i = 0; i < colRep.count; i++) {
            const c = colRep.itemAt(i)
            if (!c || !c.visible) continue
            const x0 = c.mapToItem(content, 0, 0).x
            const d = p.x < x0 ? x0 - p.x : p.x > x0 + c.width ? p.x - x0 - c.width : 0
            if (d < best) { best = d; col = i }
        }
        if (col < 0) return
        const c = colRep.itemAt(col)
        let idx = 0, pos = 0
        for (let i = 0; i < c.ids.length; i++) {
            if (c.ids[i] === dragId) continue
            const card = c.cardAt(i)
            if (card && card.mapToItem(content, 0, card.height / 2).y < p.y) idx = pos + 1
            pos++
        }
        dropCol = col
        dropIndex = idx
    }

    Item {
        id: content
        anchors.fill: parent

        // long-press an empty spot (or a card's background): edit live
        TapHandler {
            enabled: !root.editing
            onLongPressed: EditMode.start("dashboard")
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            // ── edit bar (only while editing) ───────────────────────────────
            Rectangle {
                id: editBar
                visible: root.editing
                Layout.fillWidth: true
                height: 40
                radius: root.radius / 2
                color: Colors.shade(0.27)
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                    spacing: 8
                    Text { text: "󰏫"; color: Colors.color6; font.pixelSize: 16; font.family: Properties.fontFamily }
                    Text {
                        text: "Editing the dashboard"
                        color: Colors.ink
                        font { pixelSize: 13; bold: true; family: Properties.fontFamily }
                    }
                    Text {
                        text: PanelLayout.dashHidden.length > 0 ? "·  hidden, drag one in:" : "·  drag cards to move  ·  − or dropping here hides one"
                        color: Colors.fade(0.5)
                        font { pixelSize: 11; family: Properties.fontFamily }
                    }
                    Repeater {
                        model: PanelLayout.dashHidden
                        DashTrayChip {
                            required property string modelData
                            dash: root
                            cardId: modelData
                        }
                    }
                    Item { Layout.fillWidth: true }
                    IconButton {
                        icon: "󰒓"
                        tooltip: "Dashboard layout settings"
                        onClicked: { EditMode.stop(); root.close(); Panels.call("settings", "openPage", "dashlayout") }
                    }
                    IconButton {
                        icon: "󰑓"
                        tooltip: "Reset to the default layout"
                        interactive: PanelLayout.dashChanged
                        onClicked: PanelLayout.dashReset()
                    }
                    IconButton {
                        icon: "󰄬"
                        active: true
                        tooltip: "Done"
                        onClicked: EditMode.stop()
                    }
                }
            }

            // ── columns ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Repeater {
                    id: colRep
                    model: PanelLayout.dashColumnCount

                    Item {
                        id: dashColumn
                        required property int index
                        readonly property var ids: PanelLayout.dashColumns[index] ?? []
                        readonly property bool wide: PanelLayout.dashWide(index)
                        function cardAt(i) { return cardRep.itemAt(i) }

                        // an empty column only shows (as a drop target) while dragging
                        visible: ids.length > 0 || root.dragId !== ""
                        Layout.fillHeight: true
                        Layout.fillWidth: wide
                        Layout.preferredWidth: ids.length === 0 ? 140 : 300

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Repeater {
                                id: cardRep
                                model: dashColumn.ids
                                DashCard {
                                    dash: root
                                    area: root.overlay
                                    column: dashColumn.index
                                    wideColumn: dashColumn.wide
                                }
                            }
                            // only fixed-height cards: keep them at the top
                            Item {
                                visible: !dashColumn.ids.some(id => PanelLayout.dashCard(id).height === 0)
                                Layout.fillHeight: true
                            }
                        }

                        DropZone {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: root.radius
                            shown: root.dragId !== ""
                            hot: root.dropCol === dashColumn.index
                        }

                        // where the card will land
                        Rectangle {
                            visible: root.dragId !== "" && root.dropCol === dashColumn.index
                            x: 8
                            width: parent.width - 16
                            height: 3
                            radius: 1.5
                            color: Colors.color6
                            y: {
                                root.dragY; root.dropIndex
                                let pos = 0, last = null
                                for (let i = 0; i < dashColumn.ids.length; i++) {
                                    if (dashColumn.ids[i] === root.dragId) continue
                                    const c = cardRep.itemAt(i)
                                    if (!c) continue
                                    if (pos === root.dropIndex) return Math.max(-6, c.y - 6.5)
                                    last = c
                                    pos++
                                }
                                return last ? Math.min(dashColumn.height + 3, last.y + last.height + 3.5) : dashColumn.height / 2
                            }
                        }
                    }
                }
            }
        }

    }

    // the edit bar takes cards off the dashboard when one is dropped on it
    DropZone {
        parent: root.overlay
        readonly property var r: { root.pointer; const p = editBar.mapToItem(root.overlay, 0, 0); return { x: p.x, y: p.y } }
        x: r.x - 3
        y: r.y - 3
        width: editBar.width + 6
        height: editBar.height + 6
        radius: editBar.radius + 3
        shown: root.dragId !== ""
        hot: root.dropCol === -2
    }

    // the dragged card follows the pointer, anywhere on the screen
    DragGhost {
        parent: root.overlay
        source: root.dragItem
        pointer: root.pointer
        grab: root.grab
    }

    function cardComponent(id) {
        return id === "profile" ? profileCard : id === "music" ? musicCard
             : id === "calendar" ? calendarCard : id === "stats" ? statsCard : null
    }

    // ── card contents ───────────────────────────────────────────────────────
    Component {
        id: profileCard
        Item { DashboardProfile {} }
    }

    Component {
        id: musicCard
        Item {
            property real radius: parent ? parent.radius : 12
            DashboardMusic { active: root.shown }
            // The album-art background fills this card and would cover its
            // border, so draw the outline again on top.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder
            }
        }
    }

    Component {
        id: calendarCard
        // month grid + the picked day's events (when the calendar app has accounts)
        RowLayout {
            spacing: 0
            readonly property bool hasEvents: CalendarStore.accounts.length > 0

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                DashboardCalendar { id: dashCal }
            }
            Rectangle {
                visible: parent.hasEvents
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                color: Properties.cardBorder
            }
            DashboardEvents {
                visible: parent.hasEvents
                Layout.fillHeight: true
                Layout.preferredWidth: Math.round(parent.width * 0.40)
                day: dashCal.selectedDate
            }
        }
    }

    Component {
        id: statsCard
        Item { DashboardStats { active: root.shown } }
    }
}
