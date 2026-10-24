import QtQuick
import qs.services

// Start of the bar: its left end, or the top on a vertical bar (modules: BarLayout, zone "left").
// Sized by bindings, not by stretching anchors: a stretch would leave its old
// size behind when the bar changes edge.
BarSection {
    zone: "left"
    anchors.left: parent.left
    anchors.top: parent.top
    width: vertical ? parent.width : implicitWidth
    height: vertical ? implicitHeight : parent.height
    anchors.leftMargin: vertical ? 0 : Properties.barMarginLeft + 8
    anchors.topMargin: vertical ? Properties.barMarginLeft + 8 : 0
}
