import Quickshell
import QtQuick
import QtQuick.Layouts

import "Right"

RowLayout {
    id: middle
    anchors.right: parent.right 
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: 8
    spacing: 8

    Headset {}
    Bluetooth {}
    Volume {}
    Network {}
    Battery {}
    Powermenu {}
    
}