import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../notifications"

// Control center (right side of the bar): clock + power, Wi-Fi, Bluetooth,
// tools (screenshot, OCR, color picker), batteries, volume, notifications —
// as cards in the order PanelLayout keeps, with the buttons where PanelLayout
// puts them (plus own cards). Two live editors (long-press an empty spot, then
// switch in the edit bar):
//   Cards   — cards wiggle; drag one to move it, − hides it
//   Buttons — every button wiggles; drag it into any card that holds buttons,
//             − hides it; the cards themselves stay put
// A dragged part follows the pointer anywhere on the screen and snaps to the
// nearest free spot when let go; hidden ones are dragged in from the edit bar,
// and dropping on the edit bar hides.
// Window/shape/animation all come from BarPopup.
BarPopup {
    id: root
    side: "right"
    ipcName: "controlCenter"
    panelWidth: 420
    // grows with the content up to the screen height, then scrolls
    maxHeight: (screen?.height ?? 1440) - 90
    panelHeight: Math.min(mainCol.implicitHeight + padding * 2, maxHeight)
    // don't vanish while typing a Wi-Fi password with the pointer elsewhere, or while editing
    autoClose: !typingPassword && !editing
    property bool typingPassword: false
    fullscreen: editing

    // needed for the Wi-Fi password field
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // old name, so existing keybinds keep working
    IpcHandler {
        target: "notifCenter"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    property string expanded: ""   // "" | "wifi" | "bluetooth": that tile's list is open

    readonly property bool editCards: EditMode.target === "controlCenter"
    readonly property bool editButtons: EditMode.target === "controlCenterButtons"
    readonly property bool editing: editCards || editButtons
    onPopupClosed: {
        expanded = ""
        arm.disarm()
        Notifs.collapseAll()
        if (editing) EditMode.stop()
    }
    Connections {
        target: EditMode
        function onTargetChanged() {
            if (root.editing && !root.shown) root.open()
            root.cancelDrag()
        }
    }

    // ── Network / Bluetooth state ──
    readonly property var wifiDevice: Devices.pick(Networking.devices.values, DeviceType.Wifi)
    readonly property var wiredDevice: Devices.pick(Networking.devices.values, DeviceType.Wired)
    readonly property var wifiNetwork: wifiDevice?.networks?.values.find(n => n.connected) ?? null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: (btAdapter?.devices?.values ?? []).filter(d => d.connected)

    // batteries: laptop, custom sources, Bluetooth devices (shown in the header, under the clock)
    readonly property var batteryItems: {
        const out = []
        const d = UPower.displayDevice
        if (d?.isLaptopBattery)
            out.push({ icon: "󰁹", name: "Battery", level: Math.round(d.percentage * 100) })
        for (const b of CustomBatteries.available)
            out.push({ icon: b.icon, name: b.name, level: b.level })
        for (const dev of root.btConnected)
            if (dev.batteryAvailable)
                out.push({ icon: BluetoothPower.iconFor(dev), name: dev.name, level: Math.round(dev.battery * 100) })
        return out
    }

    // Close first, so the panel isn't in the screenshot / color pick:
    // capture and session actions run once the control center is out of the way
    function runClosed(fn) {
        root.close()
        closedTimer.fn = fn
        closedTimer.restart()
    }
    Timer { id: closedTimer; property var fn; interval: 350; onTriggered: fn() }

    function runTool(cmd) {
        root.close()
        Quickshell.execDetached(["bash", "-c", "sleep 0.35; " + cmd])
    }

    // log out / reboot / shut down: the first click arms, a second within 3s runs
    ConfirmArm { id: arm }
    readonly property alias armed: arm.armed
    function confirm(id) { return arm.confirm(id) }

    // ── live editing ──────────────────────────────────────────────
    // cards that hold buttons (CCHeader / CCTileCard) register here
    property var holders: []
    function registerHolder(h) { holders = holders.filter(x => x !== h).concat([h]) }
    function unregisterHolder(h) { holders = holders.filter(x => x !== h) }

    property string dragKind: ""         // "" | "card" | "item"
    property string dragId: ""
    property Item dragItem: null
    property point grab: Qt.point(0, 0)
    property point pointer: Qt.point(0, 0)   // overlay coordinates
    property string dropHolder: ""       // items: holder id, "hide"; cards: "list", "hide"
    property int dropIndex: 0
    property var marker: null            // { x, y, w, h } in overlay coordinates, or null

    function beginDrag(kind, id, item, gx, gy) {
        dragKind = kind
        dragId = id
        dragItem = item
        grab = Qt.point(gx, gy)
        dropHolder = ""
        marker = null
        EditMode.dragging = true
    }
    function cancelDrag() {
        dragKind = ""
        dragId = ""
        dragItem = null
        dropHolder = ""
        marker = null
        EditMode.dragging = false
    }
    function endDrag() {
        if (dragKind === "card") {
            if (dropHolder === "hide") PanelLayout.ccRemove(dragId)
            else if (dropHolder === "list") PanelLayout.ccMove(dragId, dropIndex)
        } else if (dragKind === "item") {
            if (dropHolder === "hide") PanelLayout.ccRemoveItem(dragId)
            else if (dropHolder !== "") PanelLayout.ccMoveItem(dragId, dropHolder, dropIndex)
        }
        cancelDrag()
    }

    function rectOf(item) {
        const p = item.mapToItem(overlay, 0, 0)
        return { x: p.x, y: p.y, w: item.width, h: item.height }
    }
    function dist(p, r) {
        const dx = p.x < r.x ? r.x - p.x : p.x > r.x + r.w ? p.x - r.x - r.w : 0
        const dy = p.y < r.y ? r.y - p.y : p.y > r.y + r.h ? p.y - r.y - r.h : 0
        return Math.hypot(dx, dy)
    }
    // the buttons (CCItem) inside an item, in reading order
    function itemsIn(container) {
        const out = []
        const walk = it => {
            for (const c of it.children) {
                if (c.ccItem === true) { if (c.visible) out.push(c) }
                else walk(c)
            }
        }
        walk(container)
        return out
    }

    // pointer moved (overlay coordinates): the ghost follows, the drop spot snaps
    function track(p) {
        pointer = p
        if (tray.visible && dist(p, rectOf(tray)) === 0) { dropHolder = "hide"; marker = null; return }

        if (dragKind === "card") {
            const y = mainCol.mapFromItem(overlay, p.x, p.y).y
            let idx = 0, pos = 0, at = null, last = null
            for (let i = 0; i < blockRep.count; i++) {
                const b = blockRep.itemAt(i)
                if (!b || b.cardId === dragId || !b.visible) continue
                if (b.y + b.height / 2 < y) idx = pos + 1
                else if (!at) at = b
                last = b
                pos++
            }
            dropHolder = "list"
            dropIndex = idx
            const ref = at ?? last
            if (!ref) { marker = null; return }
            const r = rectOf(ref)
            marker = { x: r.x + 10, y: at ? r.y - 5.5 : r.y + r.h + 2.5, w: r.w - 20, h: 3 }
            return
        }

        // a button: the nearest card that holds buttons, then the nearest spot in it
        let best = null, bestD = 1e9
        for (const h of holders) {
            if (!h.area || !h.area.visible) continue
            const d = dist(p, rectOf(h.area))
            if (d < bestD) { bestD = d; best = h }
        }
        if (!best) return
        const ids = best.ids.filter(x => x !== dragId)
        const its = itemsIn(best.area).filter(it => it.itemId !== dragId)
        dropHolder = best.holderId
        if (its.length === 0) { dropIndex = 0; marker = null; return }
        let near = null, nearD = 1e9
        for (const it of its) {
            const r = rectOf(it)
            const d = Math.hypot(p.x - (r.x + r.w / 2), p.y - (r.y + r.h / 2))
            if (d < nearD) { nearD = d; near = it }
        }
        const r = rectOf(near)
        const after = p.x > r.x + r.w / 2
        dropIndex = ids.indexOf(near.itemId) + (after ? 1 : 0)
        marker = { x: after ? r.x + r.w + 1.5 : r.x - 4.5, y: r.y, w: 3, h: r.h }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height && root.dragId === ""
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // long-press an empty spot (or a card's background): edit live
        TapHandler {
            enabled: !root.editing
            onLongPressed: EditMode.start("controlCenter")
        }

        ColumnLayout {
            id: mainCol
            // a little inset while editing, so the − badges aren't cut off at the edge
            x: root.editing ? 6 : 0
            width: flick.width - x * 2
            spacing: 8

            // ── edit bar (only while editing; dropping on it hides) ──
            CCCard {
                id: tray
                visible: root.editing
                Layout.fillWidth: true
                implicitHeight: editCol.implicitHeight + 20
                ColumnLayout {
                    id: editCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12 }
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "󰏫"; color: Colors.color6; font.pixelSize: 16; font.family: Properties.fontFamily }
                        // which editor
                        Repeater {
                            model: [{ t: "controlCenter", label: "Cards" }, { t: "controlCenterButtons", label: "Buttons" }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: EditMode.target === modelData.t
                                implicitWidth: modeLabel.implicitWidth + 18
                                implicitHeight: 26
                                radius: 8
                                color: on ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.22) : modeMouse.containsMouse ? Colors.fade(0.08) : "transparent"
                                border.width: 1
                                border.color: on ? Colors.color6 : Colors.fade(0.15)
                                Text {
                                    id: modeLabel
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.on ? Colors.ink : Colors.fade(0.6)
                                    font { pixelSize: 11; bold: parent.on; family: Properties.fontFamily }
                                }
                                MouseArea {
                                    id: modeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EditMode.start(parent.modelData.t)
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            icon: "󰐕"
                            tooltip: "New card"
                            onClicked: PanelLayout.ccNewCard(1)
                        }
                        IconButton {
                            icon: "󰒓"
                            tooltip: "Control center layout settings"
                            onClicked: { EditMode.stop(); root.close(); Panels.call("settings", "openPage", "cclayout") }
                        }
                        IconButton {
                            icon: "󰑓"
                            tooltip: root.editCards ? "Default card order (own cards are kept, hidden)" : "Every button back where it was"
                            interactive: root.editCards ? PanelLayout.ccChanged : PanelLayout.ccItemsChanged
                            onClicked: root.editCards ? PanelLayout.ccReset() : PanelLayout.ccResetItems()
                        }
                        IconButton {
                            icon: "󰄬"
                            active: true
                            tooltip: "Done"
                            onClicked: EditMode.stop()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.editCards
                            ? (PanelLayout.ccHidden.length > 0 ? "Hidden cards — drag one in · drop a card here to hide it" : "Drag cards to move · − or dropping here hides one")
                            : (PanelLayout.ccHiddenItems.length > 0 ? "Hidden buttons — drag one into a card · drop here to hide" : "Drag buttons between cards · − or dropping here hides one")
                        wrapMode: Text.Wrap
                        color: Colors.fade(0.5)
                        font { pixelSize: 11; family: Properties.fontFamily }
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: chipRep.count > 0
                        spacing: 6
                        Repeater {
                            id: chipRep
                            model: root.editCards ? PanelLayout.ccHidden : root.editButtons ? PanelLayout.ccHiddenItems : []
                            TrayChip {
                                required property string modelData
                                host: root
                                kind: root.editCards ? "card" : "item"
                                chipId: modelData
                            }
                        }
                    }
                }
            }

            // ── the cards ──
            Repeater {
                id: blockRep
                model: PanelLayout.ccOrder

                Item {
                    id: block
                    required property string modelData
                    readonly property string cardId: modelData
                    readonly property bool dragged: root.dragId === cardId

                    Layout.fillWidth: true
                    implicitHeight: loader.item ? loader.item.implicitHeight : 0
                    visible: implicitHeight > 0.5 || root.editing
                    rotation: root.editCards && !dragged ? EditMode.wiggle(EditMode.seed(cardId), 0.7) : 0
                    opacity: dragged ? 0.3 : 1

                    Loader {
                        id: loader
                        width: parent.width
                        property string cardId: block.cardId
                        sourceComponent: block.cardId === "header" ? headerCard
                                       : block.cardId === "audio" ? audioCardComp
                                       : block.cardId === "notifications" ? notificationsCard
                                       : PanelLayout.isHolder(block.cardId) ? tileCard : null
                    }

                    // card editor: the whole card is the drag handle (what's inside stays)
                    MouseArea {
                        anchors.fill: parent
                        visible: root.editCards
                        z: 40
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: block.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point press: Qt.point(0, 0)
                        onPressed: m => press = Qt.point(m.x, m.y)
                        onPositionChanged: m => {
                            if (!pressed) return
                            if (root.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 5)
                                root.beginDrag("card", block.cardId, block, press.x, press.y)
                            if (block.dragged) root.track(mapToItem(root.overlay, m.x, m.y))
                        }
                        onReleased: root.endDrag()
                        onCanceled: root.cancelDrag()
                    }

                    EditBadge {
                        x: -6
                        y: -5
                        z: 60
                        visible: root.editCards && root.dragId === ""
                        onClicked: PanelLayout.ccRemove(block.cardId)
                    }
                }
            }

            Text {
                visible: PanelLayout.ccOrder.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                horizontalAlignment: Text.AlignHCenter
                text: root.editing ? "No cards — drag one in from above" : "No cards — long-press here to edit"
                color: Colors.fade(0.4)
                font { pixelSize: 12; italic: true; family: Properties.fontFamily }
            }
        }
    }

    // ── drop zones, marker and the ghost: on the full-screen overlay ──
    Item {
        parent: root.overlay
        anchors.fill: parent
        visible: root.dragKind !== ""

        // cards: the whole list
        DropZone {
            readonly property var r: { root.pointer; return root.dragKind === "card" ? root.rectOf(flick) : { x: 0, y: 0, w: 0, h: 0 } }
            x: r.x - 4; y: r.y - 4; width: r.w + 8; height: r.h + 8
            radius: 16
            shown: root.dragKind === "card"
            hot: root.dropHolder === "list"
        }
        // buttons: every card that holds some
        Repeater {
            model: root.dragKind === "item" ? root.holders : []
            DropZone {
                required property var modelData
                readonly property var r: { root.pointer; return modelData.area ? root.rectOf(modelData.area) : { x: 0, y: 0, w: 0, h: 0 } }
                x: r.x - 5; y: r.y - 5; width: r.w + 10; height: r.h + 10
                radius: 14
                shown: modelData.area?.visible ?? false
                hot: root.dropHolder === modelData.holderId
            }
        }
        // the edit bar (hides)
        DropZone {
            readonly property var r: { root.pointer; return root.rectOf(tray) }
            x: r.x - 3; y: r.y - 3; width: r.w + 6; height: r.h + 6
            radius: 16
            hot: root.dropHolder === "hide"
        }
        Rectangle {
            visible: root.marker !== null
            x: root.marker?.x ?? 0
            y: root.marker?.y ?? 0
            width: root.marker?.w ?? 0
            height: root.marker?.h ?? 0
            radius: 1.5
            color: Colors.color6
        }
    }

    DragGhost {
        parent: root.overlay
        source: root.dragItem
        pointer: root.pointer
        grab: root.grab
    }

    // ── card contents ─────────────────────────────────────────────

    // ── Clock + its buttons ──
    Component {
        id: headerCard
        CCCard {
            implicitHeight: header.implicitHeight + 24
            CCHeader {
                id: header
                host: root
                batteries: root.batteryItems
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
            }
        }
    }

    // ── Wi-Fi & Bluetooth, tools, own cards ──
    Component {
        id: tileCard
        CCTileCard {
            cardId: parent ? parent.cardId : ""
            host: root
        }
    }

    // ── Volume ──
    Component {
        id: audioCardComp
        AudioCard {
            id: audioCard
            Connections {
                target: root
                function onPopupClosed() { audioCard.reset() }
            }
        }
    }

    // ── Notifications ──
    Component {
        id: notificationsCard
        CCCard {
            implicitHeight: notifs.implicitHeight + 20
            NotificationsSection {
                id: notifs
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            }
        }
    }
}
