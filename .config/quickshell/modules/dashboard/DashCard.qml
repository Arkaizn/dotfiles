import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// One card of the dashboard. While editing live the whole card is a drag
// handle (what's inside stays as it is) and − hides it.
Rectangle {
    id: card
    required property string modelData
    required property int index
    required property var dash          // the dashboard (drag state, card contents)
    required property Item area         // drag coordinates
    property int column: 0
    property bool wideColumn: false
    readonly property var info: PanelLayout.dashCard(modelData)
    readonly property bool dragged: card.dash.dragId === modelData

    Layout.fillWidth: true
    Layout.fillHeight: info.height === 0
    Layout.preferredHeight: info.height > 0 ? info.height : -1
    Layout.minimumHeight: info.min
    radius: wideColumn ? card.dash.radius / 4 * 3 : card.dash.radius
    color: Colors.shade(0.27)
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    rotation: card.dash.editing && !dragged ? EditMode.wiggle(EditMode.seed(modelData), 0.5) : 0
    opacity: dragged ? 0.3 : 1

    Loader {
        anchors.fill: parent
        clip: true
        property real radius: card.radius      // DashboardMusic reads its parent's radius
        sourceComponent: card.dash.cardComponent(card.modelData)
    }

    // edit mode: the whole card is a drag handle (what's inside stays as it is)
    MouseArea {
        anchors.fill: parent
        visible: card.dash.editing
        z: 40
        hoverEnabled: true
        preventStealing: true
        cursorShape: card.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point press: Qt.point(0, 0)
        onPressed: m => press = Qt.point(m.x, m.y)
        onPositionChanged: m => {
            if (!pressed) return
            if (card.dash.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 5)
                card.dash.beginDrag(card.modelData, card, press.x, press.y)
            if (card.dragged) card.dash.track(mapToItem(card.area, m.x, m.y))
        }
        onReleased: card.dash.endDrag()
        onCanceled: card.dash.cancelDrag()
    }

    EditBadge {
        x: -6
        y: -6
        visible: card.dash.editing && card.dash.dragId === ""
        tooltip: "Hide this card"
        onClicked: PanelLayout.dashRemove(card.modelData)
    }
}
