import QtQuick
import QtQuick.Layouts
import qs.services

import "Right"

RowLayout {
    id: middle
    anchors.right: parent.right 
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: Properties.barMarginRight + 8
    spacing: Properties.spacing

    Headset {}
    Bluetooth {}
    Volume {}
    Network {}
    NotifButton {}
    Battery {}
    Powermenu {}
    
}