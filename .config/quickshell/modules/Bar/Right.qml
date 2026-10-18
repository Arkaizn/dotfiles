import QtQuick
import qs.services

// Right end of the bar (modules: BarLayout, zone "right")
BarSection {
    zone: "right"
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: Properties.barMarginRight + 8
}
