import QtQuick
import qs.services

// Left end of the bar (modules: BarLayout, zone "left")
BarSection {
    zone: "left"
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.leftMargin: Properties.barMarginLeft + 8
}
