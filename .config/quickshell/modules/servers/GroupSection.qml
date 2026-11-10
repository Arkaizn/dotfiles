import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// A group in the Servers app: a header (chevron, icon, name, count, what needs
// attention, its menu) and its servers as cards (a grid) or rows (list view).
// Clicking the header folds it; folding animates the height.
//
//   GroupSection { gid: "docker"; title: "Docker"; icon: "󰡨"; servers: [...]; shown: s => bool }
ColumnLayout {
    id: root

    property string gid: ""                 // group id, "__ungrouped" or "__archived"
    property string title: ""
    property string icon: ""
    property var servers: []                // every server of the group
    property var shown: s => true           // the search / filter
    property bool editable: false           // a real group: has a menu
    property bool compact: ServerStore.view === "list"
    // off while the details pane is being resized: the cards follow the width directly
    property bool animateMoves: true
    readonly property var visibleServers: servers.filter(s => shown(s))
    readonly property bool collapsed: ServerStore.isCollapsed(gid)

    signal edit(var server)
    signal cardMenu(var server, Item item, real x, real y)
    signal groupMenu(Item item, real x, real y)
    signal updateRequested(var names, Item item)
    // dragging a card (the window does the rest)
    signal cardDragStarted(var server, point scenePos, point grab)
    signal cardDragMoved(point scenePos)
    signal cardDragEnded()
    property string dragName: ""             // the card being dragged
    property bool hot: false                 // a dragged card is over this group: drop target

    visible: visibleServers.length > 0 || (editable && servers.length === 0 && shownEmpty)
    property bool shownEmpty: true          // an empty group still shows (so you can fill it)
    spacing: Tokens.space.s8

    // the header's numbers tick to new values
    property real shownTotal: servers.length
    property real shownVisible: visibleServers.length
    Behavior on shownTotal { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    Behavior on shownVisible { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }

    readonly property int offline: visibleServers.filter(s => ServerStore.info[s.name]?.reachable === false).length
    readonly property int critical: visibleServers.filter(s => ServerStore.info[s.name]?.critical).length
    readonly property int failing: visibleServers.filter(s => (ServerStore.info[s.name]?.checksFailed ?? 0) > 0).length
    readonly property int pending: visibleServers.filter(s => { const i = ServerStore.info[s.name]; return i && i.packages + i.containers > 0 }).length

    // ── header ──
    Pressable {
        id: head
        Layout.fillWidth: true
        implicitHeight: 34
        accessibleName: root.title + (root.collapsed ? ", folded" : "")
        onClicked: ServerStore.setCollapsed(root.gid, !root.collapsed)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onRightClicked: if (root.editable) root.groupMenu(head, 40, head.height)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.md
            color: root.hot ? Colors.alpha(Colors.accent, 0.16) : head.hovered ? Colors.fade(0.05) : "transparent"
            border.width: root.hot ? 1.5 : 0
            border.color: Colors.alpha(Colors.accent, 0.7)
            scale: root.hot ? 1.01 : 1
            Behavior on color { ColorAnimation { duration: Anim.fast } }
            Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.pop } }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space.s6
            anchors.rightMargin: Tokens.space.s4
            spacing: Tokens.space.s8
            Chevron { open: !root.collapsed }
            Text {
                text: root.icon
                color: Colors.accent
                font.pixelSize: Tokens.font.subtitle
                font.family: Properties.fontFamily
            }
            Text {
                text: root.title
                color: Colors.ink
                font.pixelSize: Tokens.font.subtitle
                font.bold: true
                font.family: Properties.fontFamily
            }
            Rectangle {
                implicitWidth: cnt.implicitWidth + 12
                implicitHeight: 18
                radius: 9
                color: Colors.fade(0.08)
                Text {
                    id: cnt
                    anchors.centerIn: parent
                    text: root.visibleServers.length === root.servers.length ? String(Math.round(root.shownTotal))
                        : Math.round(root.shownVisible) + " / " + Math.round(root.shownTotal)
                    color: Colors.textMuted
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
            }
            // what needs attention, in words (while a card hovers over it: what a drop does)
            Text {
                Layout.fillWidth: true
                text: root.hot ? (root.gid === "__archived" ? "drop to archive it" : root.gid === "__ungrouped" ? "drop to take it out of its group" : "drop to move it here")
                    : [root.offline ? root.offline + " offline" : "", root.failing ? root.failing + " failing checks" : "",
                       root.critical ? root.critical + " critical" : "", root.pending ? root.pending + " with updates" : ""]
                      .filter(x => x).join("  ·  ")
                color: root.hot ? Colors.accent : root.failing || root.critical ? Colors.red : root.pending ? Colors.orange : root.offline ? Colors.fade(0.5) : Colors.textMuted
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            IconButton {
                visible: root.gid !== "__archived" && root.pending > 0
                implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm
                icon: "󰚰"
                tooltip: "Update this group…"
                onClicked: root.updateRequested(root.visibleServers.map(s => s.name), this)
            }
            IconButton {
                visible: root.gid !== "__archived" && root.visibleServers.length > 0
                implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm
                icon: "󰑓"
                tooltip: "Scan this group (+ health checks)"
                onClicked: ServerRuns.scanAll(root.visibleServers.map(s => s.name))
            }
            IconButton {
                visible: root.editable
                implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm
                icon: "󰇘"
                tooltip: "Group: rename, icon, order, delete"
                onClicked: root.groupMenu(this, width / 2, height)
            }
        }
    }

    // ── body: folds by animating its height ──
    Item {
        id: body
        Layout.fillWidth: true
        // clipped only while it folds / is folded: a hovered card lifts above its top edge
        clip: Math.abs(implicitHeight - content.implicitHeight) > 0.5
        implicitHeight: root.collapsed ? 0 : content.implicitHeight
        opacity: root.collapsed ? 0 : 1
        // hidden only once folded all the way (hiding it while unfolded would keep its cards from being laid out)
        visible: !root.collapsed || implicitHeight > 0.5
        Behavior on implicitHeight { NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        Behavior on opacity { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }

        Item {
            id: content
            width: body.width
            implicitHeight: root.servers.length === 0 ? empty.implicitHeight : flow.implicitHeight
            // drops in from slightly above when unfolding
            y: root.collapsed ? -12 : 0
            Behavior on y { NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }

            Text {
                id: empty
                visible: root.servers.length === 0
                x: Tokens.space.s12
                text: "No servers in this group yet: add them from a server's menu or its editor"
                color: Colors.textFaint
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                bottomPadding: Tokens.space.s6
            }

            // cards: as many columns as fit (at least 270 px wide), filling the width
            readonly property int columns: root.compact ? 1 : Math.max(1, Math.floor((width + flow.spacing) / (270 + flow.spacing)))
            // floored: a fraction of a pixel too wide would push the last card of a row onto the next one
            readonly property real cardWidth: Math.floor((width - (columns - 1) * flow.spacing) / columns) - 1

            Flow {
                id: flow
                width: parent.width
                spacing: root.compact ? Tokens.space.s4 : Tokens.space.s10
                // moving (filter, the details pane opening, the window resizing): each card glides
                // there itself (the Behaviors on its cell), so a width change animates too
                // appearing (first show, a filter letting it back in): fade + rise, one after the other
                add: Transition {
                    id: addT
                    SequentialAnimation {
                        PropertyAction { property: "opacity"; value: 0 }
                        PauseAnimation { duration: Math.min(addT.ViewTransition.index, 10) * Anim.ms(25) }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.medium; easing.type: Anim.standard }
                            NumberAnimation { property: "y"; from: addT.ViewTransition.destination.y + 8; to: addT.ViewTransition.destination.y
                                              duration: Anim.medium; easing.type: Anim.standard }
                        }
                    }
                }
                Repeater {
                    model: root.servers
                    // a wrapper, so the entrance animation never touches the card's own opacity
                    Item {
                        id: cell
                        required property var modelData
                        width: content.cardWidth
                        height: card.implicitHeight
                        visible: root.shown(modelData)
                        // only after the first layout: opening the window doesn't fly them in from the corner
                        property bool settled: false
                        Component.onCompleted: Qt.callLater(() => cell.settled = true)
                        readonly property bool glide: settled && root.animateMoves
                        Behavior on x { enabled: cell.glide; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
                        Behavior on y { enabled: cell.glide; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
                        Behavior on width { enabled: cell.glide; NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
                        ServerCard {
                            id: card
                            anchors.fill: parent
                            server: cell.modelData
                            compact: root.compact
                            onEdit: root.edit(cell.modelData)
                            onMenu: (item, x, y) => root.cardMenu(cell.modelData, item, x, y)
                            onUpdateRequested: item => root.updateRequested([cell.modelData.name], item)
                            dragged: root.dragName === cell.modelData.name
                            onDragStarted: (p, g) => root.cardDragStarted(cell.modelData, p, g)
                            onDragMoved: p => root.cardDragMoved(p)
                            onDragEnded: root.cardDragEnded()
                        }
                    }
                }
            }
        }
    }
}
