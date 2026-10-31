import QtQuick
import qs.services

// A card on a panel: the surface every group of controls sits on (control
// center sections, dashboard tiles, settings groups). Children are placed
// freely; size it from them, e.g.
//   Card { implicitHeight: col.implicitHeight + 24; ColumnLayout { id: col; … } }
// For a column of rows use ListCard; with a title above it, Section.
// `raised`: the darker dashboard / keybinds card (Colors.surfaceCardRaised).
Rectangle {
    property bool raised: false
    radius: Tokens.radius.card
    color: raised ? Colors.surfaceCardRaised : Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
}
