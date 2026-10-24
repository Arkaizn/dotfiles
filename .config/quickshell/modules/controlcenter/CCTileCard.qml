import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// A control center card of tiles: Wi-Fi & Bluetooth, tools, and own cards
// (PanelLayout.ccItems[cardId]). The Wi-Fi / Bluetooth tile opens its list in
// the card it's in. Own cards have a background and a name (renamed while the
// buttons are edited live); the built-in ones are just their tiles.
Rectangle {
    id: card
    required property string cardId
    required property var host          // the control center

    readonly property string holderId: cardId
    readonly property bool own: PanelLayout.isCustom(cardId)
    readonly property var ids: PanelLayout.ccItems[cardId] ?? []
    readonly property bool editing: host.editButtons
    readonly property string title: own ? (PanelLayout.ccCustom[cardId]?.title ?? "") : ""
    // the list of the expanded Wi-Fi / Bluetooth tile, if that tile is in here
    readonly property string list: host.expanded !== "" && ids.includes(host.expanded) ? host.expanded : ""
    // its size (Settings.panels.cards, resized live with the grips while the
    // buttons are edited): tiles per row and their height
    readonly property var size: PanelGeometry.card(cardId)
    property int livePerRow: 0
    property int liveTile: 0
    readonly property int perRow: livePerRow > 0 ? livePerRow : size.perRow
    readonly property int tileHeight: liveTile > 0 ? liveTile : size.tile
    // rows of at most perRow tiles (default 3), as even as possible: 2 → halves,
    // 3 → thirds, 4 → 2 × 2, 5 → 3 + 2, 7 → 3 + 2 + 2; the tiles of a row share it equally
    readonly property var rows: {
        const out = []
        let at = 0
        for (let n = Math.ceil(ids.length / perRow); n > 0; n--) {
            const k = Math.ceil((ids.length - at) / n)
            out.push(ids.slice(at, at + k))
            at += k
        }
        return out
    }
    readonly property Item area: card      // where buttons can be dropped
    Component.onCompleted: host.registerHolder(card)
    Component.onDestruction: host.unregisterHolder(card)

    readonly property int pad: own ? 12 : 0
    implicitHeight: ids.length === 0 && !editing && !own ? 0 : col.implicitHeight + pad * 2
    radius: 14
    color: own ? Colors.card : "transparent"
    border.width: own ? Properties.panelBorderWidth : 0
    border.color: Properties.cardBorder

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.pad }
        spacing: 8

        // ── name (own cards) ──
        Item {
            visible: card.own && (card.title !== "" || card.editing)
            Layout.fillWidth: true
            implicitHeight: 22
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !card.editing
                text: card.title
                color: Colors.ink
                font { pixelSize: 13; bold: true; family: Properties.fontFamily }
            }
            Rectangle {
                anchors.fill: parent
                visible: card.editing
                radius: 6
                color: Colors.fade(nameInput.activeFocus ? 0.10 : 0.05)
                border.width: 1
                border.color: nameInput.activeFocus ? Colors.color6 : Colors.fade(0.12)
                TextInput {
                    id: nameInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: card.title
                    color: Colors.ink
                    selectByMouse: true
                    clip: true
                    font { pixelSize: 12; bold: true; family: Properties.fontFamily }
                    onEditingFinished: PanelLayout.ccRename(card.cardId, text)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === "" && !parent.activeFocus
                        text: "Card name (optional)"
                        color: Colors.fade(0.35)
                        font { pixelSize: 12; italic: true; family: Properties.fontFamily }
                    }
                }
            }
        }

        // ── tiles ──
        Repeater {
            model: card.rows
            RowLayout {
                id: tileRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: tileRow.modelData
                    CCItem {
                        required property string modelData
                        itemId: modelData
                        host: card.host
                        tileHeight: card.tileHeight
                        Behavior on tileHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1     // equal shares, not the tiles' own widths
                        Layout.minimumWidth: 0
                    }
                }
            }
        }

        // ── empty ──
        Rectangle {
            visible: card.ids.length === 0
            Layout.fillWidth: true
            implicitHeight: 56
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: Colors.fade(0.15)
            Text {
                anchors.centerIn: parent
                text: card.editing ? "Drag buttons here" : "Empty card — long-press to edit"
                color: Colors.fade(0.4)
                font { pixelSize: 11; italic: true; family: Properties.fontFamily }
            }
        }

        // ── Wi-Fi / Bluetooth list ──
        CCCard {
            id: detailCard
            Layout.fillWidth: true
            readonly property real target: card.list === "wifi" ? wifiList.implicitHeight + 24
                                         : card.list === "bluetooth" ? btList.implicitHeight + 24
                                         : card.list === "vpn" ? vpnList.implicitHeight + 24 : 0
            implicitHeight: target
            visible: implicitHeight > 0.5
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            WifiList {
                id: wifiList
                property real slideX: 0
                transform: Translate { x: wifiList.slideX }
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                visible: card.list === "wifi"
                device: card.host.wifiDevice
                active: visible && card.host.shown
            }
            VpnList {
                id: vpnList
                property real slideX: 0
                transform: Translate { x: vpnList.slideX }
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                visible: card.list === "vpn"
                active: visible && card.host.shown
            }
            BluetoothList {
                id: btList
                property real slideX: 0
                transform: Translate { x: btList.slideX }
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                visible: card.list === "bluetooth"
                active: visible && card.host.shown
            }
        }
    }

    // Switching directly between the two lists slides the new one in from the
    // side its tile is on. Opening from closed just grows the card instead.
    property string prevList: ""
    onListChanged: {
        const from = prevList
        prevList = list
        if (from === "" || list === "") return
        const leftFirst = ids.indexOf("wifi") < ids.indexOf("bluetooth")
        listSlide.stop()
        listSlide.target = list === "wifi" ? wifiList : btList
        listSlide.from = (list === "wifi") === leftFirst ? -60 : 60
        listSlide.start()
    }
    ParallelAnimation {
        id: listSlide
        property Item target: null
        property real from: 0
        NumberAnimation { target: listSlide.target; property: "slideX"; from: listSlide.from; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: listSlide.target; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }

    // don't auto-close while a Wi-Fi password is typed
    Binding { target: card.host; property: "typingPassword"; value: wifiList.passwordFor !== ""; when: wifiList.visible }
    Connections {
        target: card.host
        function onPopupClosed() { wifiList.passwordFor = "" }
    }

    // ── size grips (buttons edited live): right edge = tiles per row (drag
    // left for more, narrower ones), bottom edge = tile height ──
    ResizeHandle {
        visible: card.editing && card.ids.length > 0 && card.host.dragId === ""
        horizontal: true
        anchors.right: parent.right
        anchors.rightMargin: -4             // clear of the control center's scroll bar
        anchors.verticalCenter: parent.verticalCenter
        property int start: 0
        onStarted: start = card.perRow
        onMoved: d => card.livePerRow = Snap.clamp(start - Math.round(d / 50), 1, 6)
        onDone: { if (card.livePerRow > 0) PanelGeometry.setCard(card.cardId, "perRow", card.livePerRow); card.livePerRow = 0 }
    }
    ResizeHandle {
        visible: card.editing && card.ids.length > 0 && card.host.dragId === ""
        horizontal: false
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -9
        anchors.horizontalCenter: parent.horizontalCenter
        property int start: 0
        onStarted: start = card.tileHeight
        onMoved: d => card.liveTile = Snap.resize(start, d / Math.max(1, card.rows.length), 40, 120, 2)
        onDone: { if (card.liveTile > 0) PanelGeometry.setCard(card.cardId, "tile", card.liveTile); card.liveTile = 0 }
    }
}
