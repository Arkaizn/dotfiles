import Quickshell
import QtQuick
import QtQuick.Layouts

import "Middle"

RowLayout {
    id: middle
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    spacing: bar.spacing

    // GPUusage {}
    // CPUusage {}
    // Memusage {}
    Clock {}
    // GPUtemp {}
    // CPUtemp {}
}