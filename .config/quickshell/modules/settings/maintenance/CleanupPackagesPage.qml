import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Cleanup & packages: one page for keeping the system lean, two tabs.
//   Free space → CleanupPage (caches, package cache, journal, orphans, trash)
//   Packages   → PackagesPage (unused programs, biggest, recently changed)
// anchor "packages" (search, qs ipc call settings openPage packages) opens the second tab.
ColumnLayout {
    id: page
    spacing: 16

    property string anchor: ""
    signal anchorConsumed()
    property string tab: "space"
    // which side the new tab slides in from (TabPane)
    property int dir: 0
    onTabChanged: dir = tab === "packages" ? 1 : -1

    // consumed after this change is done (clearing it right away is a binding loop)
    function applyAnchor() {
        if (anchor === "") return
        tab = anchor === "packages" ? "packages" : "space"
        Qt.callLater(anchorConsumed)
    }
    Component.onCompleted: applyAnchor()
    onAnchorChanged: applyAnchor()

    Segmented {
        options: [{ label: "Free space", value: "space", icon: "󰃢" }, { label: "Packages", value: "packages", icon: "󰏗" }]
        value: page.tab
        onEdited: v => page.tab = v
    }

    TabPane {
        from: page.dir
        active: page.tab === "space"
        sourceComponent: CleanupPage {}
    }
    TabPane {
        from: page.dir
        active: page.tab === "packages"
        sourceComponent: PackagesPage {}
    }
}
