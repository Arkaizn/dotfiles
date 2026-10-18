import QtQuick
import qs.services

// Background card used for every section of the control center.
// Content goes inside; size it from the content, e.g.
//   CCCard { implicitHeight: col.implicitHeight + 24; ColumnLayout { id: col; ... } }
Rectangle {
    radius: 14
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
}
