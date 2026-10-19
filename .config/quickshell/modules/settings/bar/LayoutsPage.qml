import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Layouts: where things sit on the bar, the dashboard and the control center,
// one page with a tab each (BarLayoutPage, DashLayoutPage, CcLayoutPage).
// anchor "bar" | "dashboard" | "cc" (search, qs ipc call settings openPage
// barlayout / dashlayout / cclayout) opens that tab.
ColumnLayout {
    id: page
    spacing: 16

    property string anchor: ""
    signal anchorConsumed()
    property string tab: "bar"
    // which side the new tab slides in from (TabPane)
    readonly property var order: ["bar", "dashboard", "cc"]
    property int dir: 0
    property string prev: "bar"
    onTabChanged: { dir = order.indexOf(tab) > order.indexOf(prev) ? 1 : -1; prev = tab }

    // consumed after this change is done (clearing it right away is a binding loop)
    function applyAnchor() {
        if (!["bar", "dashboard", "cc"].includes(anchor)) return
        tab = anchor
        Qt.callLater(anchorConsumed)
    }
    Component.onCompleted: applyAnchor()
    onAnchorChanged: applyAnchor()

    Segmented {
        options: [{ label: "Bar", value: "bar", icon: "󰕮" }, { label: "Dashboard", value: "dashboard", icon: "󰕰" },
                  { label: "Control center", value: "cc", icon: "󰂚" }]
        value: page.tab
        onEdited: v => page.tab = v
    }

    TabPane {
        from: page.dir
        active: page.tab === "bar"
        sourceComponent: BarLayoutPage {}
    }
    TabPane {
        from: page.dir
        active: page.tab === "dashboard"
        sourceComponent: DashLayoutPage {}
    }
    TabPane {
        from: page.dir
        active: page.tab === "cc"
        sourceComponent: CcLayoutPage {}
    }
}
