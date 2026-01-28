import QtQuick
import QtQuick.Layouts

import "Left"

RowLayout {
    id: left
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.leftMargin: 8
    spacing: bar.spacing

    ArchIcon {}
    Workspaces {}
    Updater {}
    Pull {}
    Push {}
    Tray {}
}