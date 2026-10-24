import QtQuick
import qs.services

// End of the bar: its right end, or the bottom on a vertical bar (modules: BarLayout, zone "right").
// Sized by bindings, not by stretching anchors (see Left.qml).
BarSection {
    zone: "right"
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: vertical ? parent.width : implicitWidth
    height: vertical ? implicitHeight : parent.height
    anchors.rightMargin: vertical ? 0 : Properties.barMarginRight + 8
    anchors.bottomMargin: vertical ? Properties.barMarginRight + 8 : 0
}
