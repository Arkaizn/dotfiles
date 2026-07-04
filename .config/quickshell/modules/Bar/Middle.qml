import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

import "Middle"


Item {
    id: middle
    anchors.fill: parent

    Clock {
        id: clock
        anchors.centerIn: parent
    }

    Music {
        id: music
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: clock.left
        anchors.rightMargin: Properties.spacing
    }
    // GPUusage {}
    // CPUusage {}
    // Memusage {}
    // GPUtemp {}
    // CPUtemp {}
}