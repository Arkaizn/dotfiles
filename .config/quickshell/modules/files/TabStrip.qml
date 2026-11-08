import QtQuick
import qs.components
import qs.services

// The window's tabs (shown once there are two): equal widths between a minimum
// and a maximum, a "+" for a new one. More than fit: the strip scrolls (wheel),
// the current tab stays in view.
//   TabStrip { tabs: [FolderTab]; current; onPicked: i => …; onCloseRequested: i => …
//              onMoveRequested: (from, to) => …; onNewRequested }   tabAt(x, y) · dropIndex
Item {
    id: root

    property var tabs: []
    property int current: 0
    signal picked(int index)
    signal closeRequested(int index)
    signal moveRequested(int from, int to)
    signal newRequested()

    // close tab `i` with its leaving animation (then closeRequested; by the tab, in case
    // the list changed meanwhile). No animations: at once.
    function close(i) {
        const chip = rep.itemAt(i)
        if (!chip || Anim.normal === 0) { closeRequested(i); return }
        if (chip.leaving) return
        const t = chip.tab
        // the shown one: its listing drifts off at once, away from the side the next comes from
        if (i === root.current && t?.view) t.view.leave((i < root.tabs.length - 1 ? 1 : -1) * Tokens.space.s24)
        chip.leave(() => { const at = root.tabs.indexOf(t); if (at >= 0) root.closeRequested(at) })
    }

    implicitHeight: Tokens.size.controlSmall + Tokens.space.s4
    readonly property real tabWidth: Math.max(Tokens.size.row * 3,
        Math.min(Tokens.size.row * 5, (width - plus.width - Tokens.space.s4) / Math.max(1, tabs.length) - Tokens.space.s4))

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: plus.left
        anchors.rightMargin: Tokens.space.s4
        height: parent.height
        contentWidth: row.implicitWidth
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        // the wheel scrolls sideways here
        WheelHandler {
            onWheel: e => flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width,
                                                               flick.contentX - (e.angleDelta.y || e.angleDelta.x) / 120 * root.tabWidth))
        }
        function reveal() {
            const x = root.current * (root.tabWidth + row.spacing)
            if (x < contentX) contentX = x
            else if (x + root.tabWidth > contentX + width) contentX = x + root.tabWidth - width
        }
        Connections {
            target: root
            function onCurrentChanged() { Qt.callLater(flick.reveal) }
            function onTabsChanged() { Qt.callLater(flick.reveal) }
        }
        onWidthChanged: Qt.callLater(reveal)

        // the current tab's card: one, sliding from tab to tab
        Rectangle {
            // (tabs: read so a change of the list moves it too)
            readonly property Item at: root.tabs.length >= 0 ? rep.itemAt(root.current) : null
            visible: at !== null
            x: at ? at.x : 0
            y: at ? at.y : 0
            width: at ? at.width : 0
            height: at ? at.height : 0
            radius: Tokens.radius.lg
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            Behavior on x { NumberAnimation { duration: Anim.slow; easing.type: Anim.emphasized } }
        }

        Row {
            id: row
            height: parent.height
            spacing: Tokens.space.s4
            Repeater {
                id: rep
                model: root.tabs
                TabChip {
                    anchors.verticalCenter: parent?.verticalCenter
                    required property var modelData
                    required property int index
                    // closing: folds away, its gap to the next tab too
                    width: (root.tabWidth + row.spacing) * keep - row.spacing
                    tab: modelData
                    label: modelData.title
                    path: modelData.path
                    current: index === root.current
                    onClicked: root.picked(index)
                    onCloseRequested: root.close(index)
                    onDragged: steps => root.moveRequested(index, Math.max(0, Math.min(root.tabs.length - 1, index + steps)))
                    dropHover: index === root.dropIndex
                }
            }
        }
    }
    // files dragged over a tab (the window's drop area asks, with a point in the strip):
    // it's marked, opens after a moment (spring-loaded), takes the drop
    property int dropIndex: -1
    function tabAt(x, y) {
        if (y < 0 || y > height || x < 0 || x > flick.width) return -1
        const i = Math.floor((x + flick.contentX) / (root.tabWidth + row.spacing))
        return i >= 0 && i < root.tabs.length ? i : -1
    }

    IconButton {
        id: plus
        // right after the tabs, or at the end once they scroll
        x: Math.min(row.implicitWidth, root.width - width - Tokens.space.s4) + Tokens.space.s4
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Tokens.size.controlSmall
        implicitHeight: Tokens.size.controlSmall
        icon: "󰐕"
        tooltip: "New tab  (Ctrl+T)"
        onClicked: root.newRequested()
    }
}
