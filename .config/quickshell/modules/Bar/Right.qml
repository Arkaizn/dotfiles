import QtQuick
import QtQuick.Layouts

import "Right"

RowLayout {
    id: middle
    anchors.right: parent.right 
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: bar.barMarginRight + 8
    spacing: bar.spacing

    Headset {}
    Bluetooth {}
    Volume {}
    Network {}
    NotifButton {}
    Battery {}
    Powermenu {}
    
}