import QtQuick
import QtQuick.Layouts

import "Left"
import "Left/Tray"

RowLayout {
    id: left
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.leftMargin: bar.barMarginLeft + 8
    spacing: bar.spacing

    ArchIcon {}
    Workspaces {}
    Updater {}
    Pull {}
    Push {}
    Tray {}
}