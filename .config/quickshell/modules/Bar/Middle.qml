import Quickshell
import QtQuick
import QtQuick.Layouts

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
        anchors.rightMargin: bar.spacing
    }
    // GPUusage {}
    // CPUusage {}
    // Memusage {}
    // GPUtemp {}
    // CPUtemp {}
}