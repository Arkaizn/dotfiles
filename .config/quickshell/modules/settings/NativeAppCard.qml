import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import "network"

// Top of a settings page: open the system's own app for the same thing
// (pavucontrol, nm-connection-editor, blueman-manager). Greyed out with an
// install hint when it isn't installed.
//   NativeAppCard { app: "pavucontrol"; label: "PipeWire volume control"; desc: "…" }
NetCard {
    id: root

    property string app: ""
    property string label: ""
    property string desc: ""
    property bool installed: true

    Layout.fillWidth: true
    Component.onCompleted: Jobs.which([app], r => root.installed = r[root.app] === true)

    NetRow {
        first: true
        label: root.label
        desc: root.installed ? root.desc : Jobs.installHint(root.app)
        ActionButton {
            icon: "󰏌"
            text: "Open " + root.app
            interactive: root.installed
            onClicked: Quickshell.execDetached([root.app])
        }
    }
}
